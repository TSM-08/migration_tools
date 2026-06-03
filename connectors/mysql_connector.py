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
