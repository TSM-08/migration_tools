from __future__ import annotations

from abc import ABC, abstractmethod
from contextlib import contextmanager
from dataclasses import dataclass
import json
from pathlib import Path
import socket
from typing import Any, Iterator

import yaml


@dataclass
class ProxyConfig:
	host: str
	port: int
	username: str | None = None
	password: str | None = None


class BaseConnection(ABC):
	"""Abstract parent class for database connections."""

	def __init__(self, **params: Any) -> None:
		proxy = params.pop("proxy", None)

		self.params = params
		self.proxy: ProxyConfig | None = self._parse_proxy(proxy)
		self.connection: Any | None = None

	@staticmethod
	def _parse_proxy(proxy: Any) -> ProxyConfig | None:
		if proxy is None:
			return None

		if isinstance(proxy, ProxyConfig):
			return proxy

		if isinstance(proxy, dict):
			proxy_type = proxy.get("type")
			if proxy_type is not None and str(proxy_type).lower() != "socks":
				raise ValueError("Only SOCKS proxy type is supported")

			host = proxy.get("host")
			port = proxy.get("port")
			if host is None or port is None:
				raise ValueError("Proxy config requires host and port")

			return ProxyConfig(
				host=str(host),
				port=int(port),
				username=proxy.get("username"),
				password=proxy.get("password"),
			)

		raise TypeError("proxy must be ProxyConfig, dict, or None")

	def _get_param(self, key: str) -> Any:
		if key not in self.params:
			raise ValueError(f"Missing required connection parameter: {key}")
		return self.params[key]

	@contextmanager
	def _socks_proxy_scope(self) -> Iterator[None]:
		if self.proxy is None:
			yield
			return

		try:
			import socks  # type: ignore[reportMissingImports]
		except ImportError as exc:
			raise ImportError("PySocks is required when using proxy connections") from exc

		import socket

		# Temporarily route all socket calls in this block through the SOCKS proxy.
		original_socket = socket.socket
		socks.setdefaultproxy(
			socks.SOCKS5,
			addr=self.proxy.host,
			port=int(self.proxy.port),
			username=self.proxy.username,
			password=self.proxy.password,
		)
		socket.socket = socks.socksocket
		try:
			yield
		finally:
			socket.socket = original_socket

	@abstractmethod
	def connect(self) -> Any:
		"""Open a database connection and return the connection object."""

	def close(self) -> None:
		"""Close an open connection if one exists."""
		if self.connection is not None:
			self.connection.close()
			self.connection = None

	def execute_query(self, query: str, params: tuple[Any, ...] | None = None) -> list[tuple[Any, ...]]:
		"""Execute a read query and return all rows."""
		if self.connection is None:
			self.connect()

		assert self.connection is not None
		cursor = self.connection.cursor()
		try:
			if params is None:
				cursor.execute(query)
			else:
				cursor.execute(query, params)
			return cursor.fetchall()
		finally:
			cursor.close()

	def test_connection(self) -> bool:
		"""Return True when a basic health query succeeds."""
		try:
			self.execute_query("SELECT 1")
			return True
		except Exception:
			return False

	def __enter__(self) -> BaseConnection:
		self.connect()
		return self

	def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> None:
		self.close()


class SqlServerConnection(BaseConnection):
	"""SQL Server connection via pyodbc."""

	def __init__(self, driver: str = "ODBC Driver 18 for SQL Server", **params: Any) -> None:
		super().__init__(**params)
		self.driver = driver

	@staticmethod
	def _select_sql_server_driver(requested_driver: str, installed_drivers: list[str]) -> str:
		if requested_driver in installed_drivers:
			return requested_driver

		preferred = [
			"ODBC Driver 18 for SQL Server",
			"ODBC Driver 17 for SQL Server",
			"SQL Server",
		]
		for driver_name in preferred:
			if driver_name in installed_drivers:
				return driver_name

		return requested_driver

	@staticmethod
	def _normalize_sql_username(username: str, host: str, add_server_suffix: bool = False) -> str:
		if "@" in username:
			return username
		if add_server_suffix and host.endswith(".database.windows.net"):
			server_name = host.split(".", 1)[0]
			return f"{username}@{server_name}"
		return username

	@staticmethod
	def _as_yes_no(value: Any, default: str) -> str:
		if value is None:
			return default
		if isinstance(value, bool):
			return "yes" if value else "no"
		text = str(value).strip().lower()
		if text in {"1", "true", "yes", "y", "on"}:
			return "yes"
		if text in {"0", "false", "no", "n", "off"}:
			return "no"
		return default

	def connect(self) -> Any:
		if self.connection is not None:
			return self.connection

		if self.proxy is not None:
			# Use a pure-Python TDS client for SOCKS mode; native ODBC does not reliably honor Python socket patching.
			try:
				import pytds  # type: ignore[reportMissingImports]
			except ImportError as exc:
				raise ImportError("python-tds is required for MSSQL SOCKS proxy connections") from exc

			try:
				import certifi  # type: ignore[reportMissingImports]
				ca_file = certifi.where()
			except Exception:
				ca_file = None

			target_host = str(self._get_param("host"))
			target_port = int(self._get_param("port"))
			add_server_suffix = bool(self.params.get("azure_username_suffix", False))
			sql_username = self._normalize_sql_username(
				str(self._get_param("username")),
				target_host,
				add_server_suffix,
			)
			login_timeout = int(self.params.get("login_timeout", 30))
			trust_cert = bool(self.params.get("trust_server_certificate", self.params.get("trustServerCertificate", False)))

			with self._socks_proxy_scope():
				self.connection = pytds.connect(
					server=target_host,
					port=target_port,
					database=str(self._get_param("database")),
					user=sql_username,
					password=str(self._get_param("password")),
					timeout=login_timeout,
					login_timeout=login_timeout,
					cafile=ca_file,
					validate_host=not trust_cert,
					enc_login_only=False,
				)
			return self.connection

		try:
			import pyodbc  # type: ignore[reportMissingImports]
		except ImportError as exc:
			raise ImportError("pyodbc is required for SQL Server connections") from exc

		installed_drivers = list(pyodbc.drivers())
		selected_driver = self._select_sql_server_driver(self.driver, installed_drivers)

		target_host = str(self._get_param("host"))
		target_port = int(self._get_param("port"))
		login_server_host = str(self.params.get("login_server_host", target_host))
		add_server_suffix = bool(self.params.get("azure_username_suffix", False))
		sql_username = self._normalize_sql_username(
			str(self._get_param("username")),
			login_server_host,
			add_server_suffix,
		)
		encrypt_flag = self._as_yes_no(self.params.get("encrypt"), default="yes")
		trust_cert_flag = self._as_yes_no(
			self.params.get("trust_server_certificate", self.params.get("trustServerCertificate")),
			default="yes",
		)
		login_timeout = int(self.params.get("login_timeout", 30))

		# Fast network pre-check: gives clearer errors for closed/absent local forwards.
		probe_timeout = max(2, min(login_timeout, 5))
		try:
			with socket.create_connection((target_host, target_port), timeout=probe_timeout):
				pass
		except OSError as exc:
			raise ConnectionError(
				f"TCP endpoint not reachable: {target_host}:{target_port}. "
				"If using Azure Bastion local forward, ensure it is running and listening on this port. "
				f"Original error: {exc}"
			) from exc

		# For tunnel mode, preserve SQL login server identity while sending TCP to local forwarded endpoint.
		use_address_override = login_server_host != target_host
		if use_address_override:
			server_part = f"SERVER={login_server_host};"
			address_part = f"Address={target_host},{target_port};"
		else:
			server_part = f"SERVER={target_host},{target_port};"
			address_part = ""

		conn_str = "".join(
			[
				f"DRIVER={{{selected_driver}}};",
				server_part,
				address_part,
				f"DATABASE={self._get_param('database')};",
				f"UID={sql_username};",
				f"PWD={self._get_param('password')};",
				f"Encrypt={encrypt_flag};",
				f"TrustServerCertificate={trust_cert_flag};",
			]
		)

		try:
			self.connection = pyodbc.connect(conn_str, timeout=login_timeout)
		except Exception as exc:
			err_text = str(exc)
			if "IM002" in err_text:
				available = ", ".join(installed_drivers) if installed_drivers else "none"
				raise RuntimeError(
					"ODBC driver not found for SQL Server connection. "
					f"Requested='{self.driver}', selected='{selected_driver}', installed=[{available}]"
				) from exc
			raise
		return self.connection


class MySqlConnection(BaseConnection):
	"""MySQL connection via mysql-connector-python."""

	def connect(self) -> Any:
		if self.connection is not None:
			return self.connection

		try:
			import mysql.connector  # type: ignore[reportMissingImports]
		except ImportError as exc:
			raise ImportError("mysql-connector-python is required for MySQL connections") from exc

		with self._socks_proxy_scope():
			self.connection = mysql.connector.connect(
				host=self._get_param("host"),
				port=self._get_param("port"),
				database=self._get_param("database"),
				user=self._get_param("username"),
				password=self._get_param("password"),
			)
		return self.connection


def load_connections_config(config_path: Path) -> dict[str, dict[str, Any]]:
	with config_path.open("r", encoding="utf-8") as f:
		config = yaml.safe_load(f) or {}

	connections = config.get("connections", {})
	if not isinstance(connections, dict):
		raise ValueError("connection.yaml must contain a 'connections' mapping")

	return {str(name): data for name, data in connections.items() if isinstance(data, dict)}


def build_connection(connection_name: str, connection_config: dict[str, Any]) -> BaseConnection:
	config = dict(connection_config)
	connection_type_raw = config.pop("type", None)
	if connection_type_raw is None:
		raise ValueError(f"Connection '{connection_name}' is missing required field: type")

	connection_type = str(connection_type_raw).strip().lower()
	if connection_type == "mysql":
		return MySqlConnection(**config)
	if connection_type in {"mssql", "sqlserver", "sql_server"}:
		config.pop("use_jdbc", None)
		config.pop("jdbc_driver_class", None)
		config.pop("jdbc_jar", None)
		config.pop("jdbc_url", None)
		return SqlServerConnection(**config)

	raise ValueError(f"Unsupported connection type for '{connection_name}': {connection_type_raw}")


def check_named_connection(connection_name: str, connection_config: dict[str, Any]) -> bool:
	connection: BaseConnection | None = None
	try:
		connection = build_connection(connection_name, connection_config)
		connection.execute_query("SELECT 1")
		print(f"[{connection_name}] PASS")
		return True
	except Exception as exc:
		print(f"[{connection_name}] FAIL: {exc}")
		return False
	finally:
		if connection is not None:
			connection.close()


def test_connections() -> bool:
	base_dir = Path(__file__).resolve().parent
	config_path = base_dir / "connection.yaml"

	if not config_path.exists():
		raise FileNotFoundError(f"Config file not found: {config_path}")

	connections = load_connections_config(config_path)
	required_names = ["src", "trg"]

	print(f"Checking connections from: {config_path}")

	all_ok = True
	for connection_name in required_names:
		config = connections.get(connection_name)
		if config is None:
			print(f"[{connection_name}] ERROR: missing connection config")
			all_ok = False
			continue

		if not check_named_connection(connection_name, config):
			all_ok = False

	if all_ok:
		print("All required connections are reachable.")
	else:
		print("One or more required connections failed.")

	return all_ok


class DataFetcher:
	"""Fetches data for each dataset in the configured check list from both src and trg
	connections and writes the results as JSON files into the configured data directory.

	Output layout:
	  <base_dir>/<data_dir>/src/<dataset_name>.json
	  <base_dir>/<data_dir>/trg/<dataset_name>.json
	"""

	def __init__(
		self,
		base_dir: Path,
		app_config_path: Path | None = None,
		conn_config_path: Path | None = None,
	) -> None:
		self.base_dir = base_dir
		self.app_config_path = app_config_path or base_dir / "config.yaml"
		self.conn_config_path = conn_config_path or base_dir / "connection.yaml"

	# ------------------------------------------------------------------
	# Config helpers
	# ------------------------------------------------------------------

	def _load_app_config(self) -> dict[str, Any]:
		with self.app_config_path.open("r", encoding="utf-8") as f:
			return yaml.safe_load(f) or {}

	def _resolve_dataset_list(self, app_cfg: dict[str, Any]) -> tuple[str, list[str]]:
		"""Return (list_name, [dataset_names]) according to run_mode.check_list."""
		checks_cfg = app_cfg.get("data_checks", {})
		run_mode_cfg = app_cfg.get("run_mode", {})

		list_name: str = str(run_mode_cfg.get("check_list", "data_list")).strip() or "data_list"
		dataset_list: list[str] = checks_cfg.get(list_name) or checks_cfg.get("data_list", [])

		if not isinstance(dataset_list, list) or not dataset_list:
			raise ValueError(
				f"config.yaml: check list '{list_name}' is empty or missing under data_checks"
			)
		return list_name, [str(v) for v in dataset_list]

	def _resolve_data_dir(self, app_cfg: dict[str, Any]) -> str:
		checks_cfg = app_cfg.get("data_checks", {})
		data_dir = checks_cfg.get("data_dir", "data")
		return str(data_dir)

	# ------------------------------------------------------------------
	# Query helpers
	# ------------------------------------------------------------------

	@staticmethod
	def _fetch_rows(connection: BaseConnection, dataset_name: str) -> list[dict[str, Any]]:
		"""Run SELECT * for the given dataset and return all rows as dicts."""
		if connection.connection is None:
			connection.connect()

		assert connection.connection is not None
		cursor = connection.connection.cursor()
		try:
			cursor.execute(f"SELECT * FROM {dataset_name}")  # noqa: S608 – dataset name comes from trusted config
			columns = [col[0] for col in cursor.description]
			return [dict(zip(columns, row)) for row in cursor.fetchall()]
		finally:
			cursor.close()

	@staticmethod
	def _write_json_file(file_path: Path, rows: list[dict[str, Any]]) -> None:
		with file_path.open("w", encoding="utf-8") as f:
			json.dump(rows, f, ensure_ascii=False, indent=2, default=str)
			f.write("\n")

	# ------------------------------------------------------------------
	# Public API
	# ------------------------------------------------------------------

	def fetch_all(self) -> None:
		"""Fetch every dataset in the configured check list for both src and trg."""

		app_cfg = self._load_app_config()
		list_name, dataset_list = self._resolve_dataset_list(app_cfg)
		data_dir = self._resolve_data_dir(app_cfg)

		conn_configs = load_connections_config(self.conn_config_path)

		print(f"DataFetcher: check list '{list_name}' — {len(dataset_list)} dataset(s)")
		print(f"DataFetcher: output data_dir '{data_dir}'")

		for side in ("src", "trg"):
			conn_cfg = conn_configs.get(side)
			if conn_cfg is None:
				raise ValueError(f"connection.yaml: missing '{side}' connection config")

			out_dir = self.base_dir / data_dir / side
			out_dir.mkdir(parents=True, exist_ok=True)

			connection = build_connection(side, conn_cfg)
			try:
				connection.connect()
				for dataset_name in dataset_list:
					print(f"  [{side}] fetching {dataset_name} ...", end=" ", flush=True)
					try:
						rows = self._fetch_rows(connection, dataset_name)
						out_file = out_dir / f"{dataset_name}.json"
						self._write_json_file(out_file, rows)
						print(f"{len(rows)} rows -> {out_file.relative_to(self.base_dir)}")
					except Exception as exc:
						print(f"ERROR: {exc}")
			finally:
				connection.close()

		print("DataFetcher: done.")


def main() -> None:
	base_dir = Path(__file__).resolve().parent

	print("=" * 60)
	print("Step 1: Testing connections")
	print("=" * 60)

	connections_ok = test_connections()

	if not connections_ok:
		print("\nAborting: one or more connections failed. Fix connectivity before loading data.")
		return

	print()
	print("=" * 60)
	print("Step 2: Loading data")
	print("=" * 60)

	DataFetcher(base_dir).fetch_all()


if __name__ == "__main__":
	main()
