from __future__ import annotations

from typing import Any

from .base_connector import BaseConnector


class MySqlConnector(BaseConnector):
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

	def fetch_rows(self, dataset_name: str) -> list[dict[str, Any]]:
		self._ensure_connected()

		assert self.connection is not None
		cursor = self.connection.cursor()
		try:
			cursor.execute(f"SELECT * FROM {dataset_name}")
			columns = [col[0] for col in cursor.description]
			return [dict(zip(columns, row)) for row in cursor.fetchall()]
		finally:
			cursor.close()
