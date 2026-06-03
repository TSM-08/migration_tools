from __future__ import annotations

import socket
from typing import Any

from .base_connector import BaseConnector


class SqlServerConnector(BaseConnector):
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
