from __future__ import annotations

from abc import ABC, abstractmethod
from contextlib import contextmanager
from dataclasses import dataclass
import socket
from typing import Any, Iterator


@dataclass
class ProxyConfig:
	host: str
	port: int
	username: str | None = None
	password: str | None = None


class BaseConnector(ABC):
	"""Abstract parent class for database connections."""

	def __init__(self, **params: Any) -> None:
		proxy = params.get("proxy")

		self.params = {k: v for k, v in params.items() if k != "proxy"}
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

	def __enter__(self) -> BaseConnector:
		self.connect()
		return self

	def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> None:
		self.close()
