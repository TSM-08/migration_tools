from __future__ import annotations

import json
from pathlib import Path
from typing import Any
import importlib

import yaml

from connectors import BaseConnector


SEPARATOR_WIDTH = 80


def load_connections_config(config_path: Path) -> dict[str, dict[str, Any]]:
	with config_path.open("r", encoding="utf-8") as f:
		config = yaml.safe_load(f) or {}

	connections = config.get("connections", {})
	if not isinstance(connections, dict):
		raise ValueError("connection.yaml must contain a 'connections' mapping")

	pyconnectors = config.get("pyconnectors", {})
	if pyconnectors is None:
		pyconnectors = {}
	if not isinstance(pyconnectors, dict):
		raise ValueError("connection.yaml: 'pyconnectors' must be a mapping")

	result: dict[str, dict[str, Any]] = {}
	for name, data in connections.items():
		if not isinstance(data, dict):
			continue
		entry = dict(data)
		connector_cfg = pyconnectors.get(str(name))
		if not isinstance(connector_cfg, dict):
			raise ValueError(
				f"connection.yaml: pyconnectors['{name}'] must be a mapping with 'type' and 'connector'"
			)

		connector_type = connector_cfg.get("type")
		connector_class = connector_cfg.get("connector")
		if connector_type is None or not str(connector_type).strip():
			raise ValueError(f"connection.yaml: pyconnectors['{name}'].type is required")
		if connector_class is None or not str(connector_class).strip():
			raise ValueError(f"connection.yaml: pyconnectors['{name}'].connector is required")

		entry["connector_type"] = str(connector_type).strip()
		entry["connector_class"] = str(connector_class).strip()
		result[str(name)] = entry

	return result


class ConnectionClassBuilder:
	"""Resolves and validates connection classes from config names."""

	def resolve(self, connector_class_name: str, connector_type: str) -> type[BaseConnector]:
		type_name = connector_type.strip().lower()
		if not type_name:
			raise ValueError("Connector type is empty")

		class_name = connector_class_name.strip()
		if not class_name:
			raise ValueError("Connector class is empty")

		try:
			connectors_pkg = importlib.import_module("connectors")
		except Exception as exc:
			raise ValueError(f"Cannot import connector package 'connectors': {exc}") from exc

		cls = getattr(connectors_pkg, class_name, None)
		if not isinstance(cls, type) or not issubclass(cls, BaseConnector):
			raise ValueError(f"Resolved connector class '{class_name}' is not a BaseConnector subclass")

		return cls

	def build_connection(self, connection_name: str, connection_config: dict[str, Any]) -> BaseConnector:
		config = dict(connection_config)
		connector_type_raw = config.get("connector_type")
		connector_class_raw = config.get("connector_class")
		if connector_type_raw is None or not str(connector_type_raw).strip():
			raise ValueError(
				f"Connection '{connection_name}' is missing required field: connector_type. "
				"Define it via pyconnectors.<name>.type in connection.yaml."
			)
		if connector_class_raw is None or not str(connector_class_raw).strip():
			raise ValueError(
				f"Connection '{connection_name}' is missing required field: connector_class. "
				"Define it via pyconnectors.<name>.connector in connection.yaml."
			)

		connector_type = str(connector_type_raw).strip()
		connector_class_name = str(connector_class_raw).strip()
		connection_class = self.resolve(connector_class_name, connector_type)
		constructor_params = {k: v for k, v in config.items() if k not in {"connector_type", "connector_class"}}
		return connection_class(**constructor_params)


def build_connection(connection_name: str, connection_config: dict[str, Any]) -> BaseConnector:
	return ConnectionClassBuilder().build_connection(connection_name, connection_config)


def check_named_connection(connection_name: str, connection_config: dict[str, Any]) -> bool:
	connection: BaseConnector | None = None
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


	def _load_app_config(self) -> dict[str, Any]:
		with self.app_config_path.open("r", encoding="utf-8") as f:
			return yaml.safe_load(f) or {}

	def _resolve_dataset_list(self, app_cfg: dict[str, Any]) -> tuple[str, list[str]]:
		"""Return (list_name, [dataset_names]) according to run_mode.check_list."""
		checks_cfg = app_cfg.get("data_checks", {})
		run_mode_cfg = app_cfg.get("run_mode", {})

		name_raw = run_mode_cfg.get("check_list")
		list_name = name_raw.strip() if isinstance(name_raw, str) and name_raw.strip() else "data_list"
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

	@staticmethod
	def _write_json_file(file_path: Path, rows: list[dict[str, Any]]) -> None:
		with file_path.open("w", encoding="utf-8") as f:
			json.dump(rows, f, ensure_ascii=False, indent=2, default=str)
			f.write("\n")

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
						rows = connection.fetch_rows(dataset_name)
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

	print("=" * SEPARATOR_WIDTH)
	print("Step 1: Testing connections")
	print("=" * SEPARATOR_WIDTH)

	connections_ok = test_connections()

	if not connections_ok:
		print("\nAborting: one or more connections failed. Fix connectivity before loading data.")
		return

	print()
	print("=" * SEPARATOR_WIDTH)
	print("Step 2: Loading data")
	print("=" * SEPARATOR_WIDTH)

	DataFetcher(base_dir).fetch_all()


if __name__ == "__main__":
	main()
