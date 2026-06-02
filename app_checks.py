import json
from datetime import datetime
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import pandas as pd
import yaml


SAMPLE_DIFF_ROWS = 5
NULL_SENTINEL = "__NULL__"
DEF_LIST_KEY = "data_list"
RUN_LIST_KEY = "check_list"

ERROR_TAG = "-ER-"
NULL_TAG = "NULL"
FAIL_TAG = "FAIL"
PASS_TAG = "PASS"

@dataclass
class DataConfig:
	data_dir: str
	check_list_name: str
	data_list: list[str]
	mapping_fields: dict[str, dict[str, str]] = field(default_factory=dict)	
	exclude_fields: dict[str, list[str]] = field(default_factory=dict)
	sample_diff_rows: int = SAMPLE_DIFF_ROWS
	debug: int = 0


@dataclass
class ColumnComparisonResult:
	passed: bool
	src_columns: list[str]
	trg_columns: list[str]
	missing_in_trg: list[str]
	missing_in_src: list[str]
	same_order: bool


@dataclass
class DataComparisonResult:
	passed: bool
	reason: str
	src_only_count: int | None
	trg_only_count: int | None
	src_only_sample: list[dict[str, Any]]
	trg_only_sample: list[dict[str, Any]]


@dataclass
class DataCheckResult:
	dataset_name: str
	src_count: int
	trg_count: int
	row_count_passed: bool
	columns: ColumnComparisonResult
	data: DataComparisonResult
	error_message: str | None = None


class ConfigLoader:
	def __init__(self, config_path: Path) -> None:
		self.config_path = config_path

	def load(self) -> DataConfig:
		with self.config_path.open("r", encoding="utf-8") as f:
			config = yaml.safe_load(f)

		checks_cfg = config.get("data_checks", {})
		data_dir = checks_cfg.get("data_dir", "data")
		mapping_fields_raw = checks_cfg.get("mapping_fields", {})

		run_mode_cfg = config.get("run_mode", {}) 
		check_list_name = run_mode_cfg.get(RUN_LIST_KEY) or DEF_LIST_KEY
		if not isinstance(check_list_name, str) or not check_list_name.strip():
			check_list_name = DEF_LIST_KEY

		data_list = checks_cfg.get(check_list_name)
		if data_list is None and check_list_name != DEF_LIST_KEY:
			data_list = checks_cfg.get(DEF_LIST_KEY)

		debug_raw = run_mode_cfg.get("debug", 0)
		try:
			debug = int(debug_raw)
		except (TypeError, ValueError):
			debug = 0

		sample_diff_rows_raw = run_mode_cfg.get("sample_diff_rows", SAMPLE_DIFF_ROWS)
		try:
			sample_diff_rows = int(sample_diff_rows_raw)
		except (TypeError, ValueError):
			sample_diff_rows = SAMPLE_DIFF_ROWS
		if sample_diff_rows <= 0:
			sample_diff_rows = SAMPLE_DIFF_ROWS

		if not isinstance(data_list, list) or not data_list:
			raise ValueError(
				"config.yaml must define a non-empty list under data_checks; set run_mode.check_list (or data_checks.check_list) to the target list name"
			)

		mapping_fields: dict[str, dict[str, str]] = {}
		if isinstance(mapping_fields_raw, dict):
			for dataset_name, dataset_mapping_raw in mapping_fields_raw.items():
				if not isinstance(dataset_name, str) or not isinstance(dataset_mapping_raw, dict):
					continue
				dataset_mapping: dict[str, str] = {}
				for src_col, trg_col in dataset_mapping_raw.items():
					if isinstance(src_col, str) and isinstance(trg_col, str):
						dataset_mapping[src_col] = trg_col
				if dataset_mapping:
					mapping_fields[dataset_name] = dataset_mapping

		exclude_fields_raw = checks_cfg.get("exclude_fields", {})
		exclude_fields: dict[str, list[str]] = {}
		if isinstance(exclude_fields_raw, dict):
			for dataset_name, fields_list in exclude_fields_raw.items():
				if not isinstance(dataset_name, str):
					continue
				if isinstance(fields_list, list):
					exclude_fields[dataset_name] = [f for f in fields_list if isinstance(f, str)]

		return DataConfig(
			data_dir=data_dir,
			check_list_name=check_list_name,
			data_list=data_list,
			debug=debug,
			sample_diff_rows=sample_diff_rows,
			mapping_fields=mapping_fields,
			exclude_fields=exclude_fields,
		)


class DataLoader:
	def __init__(self, base_dir: Path, data_dir: str) -> None:
		self.base_dir = base_dir
		self.data_dir = data_dir

	def _extract_rows(self, payload: Any, dataset_name: str) -> list[dict[str, Any]]:
		if isinstance(payload, dict):
			if dataset_name in payload and isinstance(payload[dataset_name], list):
				return payload[dataset_name]

			if len(payload) == 1:
				only_value = next(iter(payload.values()))
				if isinstance(only_value, list):
					return only_value

			raise ValueError(f"Unable to locate row list in JSON for dataset '{dataset_name}'")

		if isinstance(payload, list):
			return payload

		raise ValueError(f"Unsupported JSON shape for dataset '{dataset_name}'")

	def load_dataset_dataframe(self, side: str, dataset_name: str) -> pd.DataFrame:
		dataset_file = self.get_dataset_file_path(side, dataset_name)
		with dataset_file.open("r", encoding="utf-8") as f:
			payload = json.load(f)

		rows = self._extract_rows(payload, dataset_name)
		return pd.DataFrame(rows)

	def load_all_datasets(self, side: str, dataset_list: list[str]) -> dict[str, pd.DataFrame]:
		return {dataset_name: self.load_dataset_dataframe(side, dataset_name) for dataset_name in dataset_list}

	def get_dataset_file_path(self, side: str, dataset_name: str) -> Path:
		return self.base_dir / self.data_dir / side / f"{dataset_name}.json"

	def check_data_files(self, dataset_name: str) -> tuple[bool, bool]:
		src_file = self.get_dataset_file_path("src", dataset_name)
		trg_file = self.get_dataset_file_path("trg", dataset_name)
		src_exists = src_file.exists()
		trg_exists = trg_file.exists()
		
		error_message = None
		if not src_exists and not trg_exists:
			error_message =  "src file does not exist; trg file does not exist"
		elif not src_exists:
			error_message = "src file does not exist"
		elif not trg_exists:
			error_message = "trg file does not exist"

		return error_message


class DataValidator:
	@staticmethod
	def build_error_result(dataset_name: str, error_message: str) -> DataCheckResult:
		return DataCheckResult(
			dataset_name=dataset_name,
			src_count=0,
			trg_count=0,
			row_count_passed=False,
			columns=ColumnComparisonResult(
				passed=False,
				src_columns=[],
				trg_columns=[],
				missing_in_trg=[],
				missing_in_src=[],
				same_order=False,
			),
			data=DataComparisonResult(
				passed=False,
				reason="Skipped: missing file",
				src_only_count=None,
				trg_only_count=None,
				src_only_sample=[],
				trg_only_sample=[],
			),
			error_message=error_message,
		)

	@staticmethod
	def _apply_column_mapping(df: pd.DataFrame, dataset_mapping: dict[str, str]) -> pd.DataFrame:
		if not dataset_mapping:
			return df

		canonical_map: dict[str, str] = {}
		for source_col, target_col in dataset_mapping.items():
			canonical_map[source_col] = target_col
			canonical_map[target_col] = target_col

		rename_map = {column: canonical_map.get(column, column) for column in df.columns}
		return df.rename(columns=rename_map)

	@staticmethod
	def _exclude_columns(df: pd.DataFrame, exclude_list: list[str]) -> pd.DataFrame:
		if not exclude_list:
			return df

		cols_to_drop = [col for col in exclude_list if col in df.columns]
		if not cols_to_drop:
			return df

		return df.drop(columns=cols_to_drop)

	def __init__(self, sample_diff_rows: int = SAMPLE_DIFF_ROWS) -> None:
		self.sample_diff_rows = sample_diff_rows

	@staticmethod
	def _normalize_value(value: Any) -> str:
		if pd.isna(value):
			return NULL_SENTINEL

		if isinstance(value, (dict, list)):
			return json.dumps(value, sort_keys=True, ensure_ascii=False)

		return str(value)

	def _normalized_dataframe(self, df: pd.DataFrame, columns: list[str]) -> pd.DataFrame:
		normalized = df.reindex(columns=columns).copy()
		for column in columns:
			normalized[column] = normalized[column].map(self._normalize_value)

		if columns:
			normalized = normalized.sort_values(by=columns, kind="mergesort")

		return normalized.reset_index(drop=True)

	def compare_columns(self, src_df: pd.DataFrame, trg_df: pd.DataFrame) -> ColumnComparisonResult:
		src_columns = list(src_df.columns)
		trg_columns = list(trg_df.columns)

		src_set = set(src_columns)
		trg_set = set(trg_columns)

		return ColumnComparisonResult(
			passed=src_set == trg_set,
			src_columns=src_columns,
			trg_columns=trg_columns,
			missing_in_trg=sorted(src_set - trg_set),
			missing_in_src=sorted(trg_set - src_set),
			same_order=src_columns == trg_columns,
		)

	def compare_full_data(self, src_df: pd.DataFrame, trg_df: pd.DataFrame, columns_result: ColumnComparisonResult) -> DataComparisonResult:
		if not columns_result.passed:
			return DataComparisonResult(
				passed=False,
				reason="Skipped: column mismatch",
				src_only_count=None,
				trg_only_count=None,
				src_only_sample=[],
				trg_only_sample=[],
			)

		src_norm = self._normalized_dataframe(src_df, columns_result.src_columns)
		trg_norm = self._normalized_dataframe(trg_df, columns_result.src_columns)

		# SQL EXCEPT works on distinct rows, so deduplicate before diffing.
		src_distinct = src_norm.drop_duplicates().reset_index(drop=True)
		trg_distinct = trg_norm.drop_duplicates().reset_index(drop=True)

		src_except_trg = src_distinct.merge(trg_distinct, how="left", indicator=True)
		src_except_trg = src_except_trg[src_except_trg["_merge"] == "left_only"].drop(columns=["_merge"])

		trg_except_src = trg_distinct.merge(src_distinct, how="left", indicator=True)
		trg_except_src = trg_except_src[trg_except_src["_merge"] == "left_only"].drop(columns=["_merge"])

		# Keep reported diff samples deterministic and easy to compare.
		if columns_result.src_columns:
			src_except_trg = src_except_trg.sort_values(by=columns_result.src_columns, kind="mergesort").reset_index(drop=True)
			trg_except_src = trg_except_src.sort_values(by=columns_result.src_columns, kind="mergesort").reset_index(drop=True)

		is_equal = src_except_trg.empty and trg_except_src.empty
		if is_equal:
			return DataComparisonResult(
				passed=True,
				reason="Exact match",
				src_only_count=0,
				trg_only_count=0,
				src_only_sample=[],
				trg_only_sample=[],
			)

		return DataComparisonResult(
			passed=False,
			reason="Data mismatch-EXCEPT semantics",
			src_only_count=int(len(src_except_trg)),
			trg_only_count=int(len(trg_except_src)),
			src_only_sample=src_except_trg.head(self.sample_diff_rows).to_dict(orient="records"),
			trg_only_sample=trg_except_src.head(self.sample_diff_rows).to_dict(orient="records"),
		)

	def validate_dataset(
		self,
		dataset_name: str,
		src_df: pd.DataFrame,
		trg_df: pd.DataFrame,
		dataset_mapping: dict[str, str] | None = None,
		exclude_list: list[str] | None = None,
	) -> DataCheckResult:
		src_count = int(len(src_df))
		trg_count = int(len(trg_df))
		row_count_passed = src_count == trg_count

		if src_count == 0 and trg_count == 0:
			return DataCheckResult(
				dataset_name=dataset_name,
				src_count=src_count,
				trg_count=trg_count,
				row_count_passed=row_count_passed,
				columns=ColumnComparisonResult(
					passed=False,
					src_columns=list(src_df.columns),
					trg_columns=list(trg_df.columns),
					missing_in_trg=[],
					missing_in_src=[],
					same_order=True,
				),
				data=DataComparisonResult(
					passed=False,
					reason="Skipping due to both datasets empty",
					src_only_count=None,
					trg_only_count=None,
					src_only_sample=[],
					trg_only_sample=[],
				),
			)

		if src_count == 0 or trg_count == 0:
			return DataCheckResult(
				dataset_name=dataset_name,
				src_count=src_count,
				trg_count=trg_count,
				row_count_passed=row_count_passed,
				columns=ColumnComparisonResult(
					passed=False,
					src_columns=list(src_df.columns),
					trg_columns=list(trg_df.columns),
					missing_in_trg=[],
					missing_in_src=[],
					same_order=False,
				),
				data=DataComparisonResult(
					passed=False,
					reason="Skipping due to one dataset empty",
					src_only_count=None,
					trg_only_count=None,
					src_only_sample=[],
					trg_only_sample=[],
				),
			)

		mapping = dataset_mapping or {}
		src_df_mapped = self._apply_column_mapping(src_df, mapping)
		trg_df_mapped = self._apply_column_mapping(trg_df, mapping)

		exclude = exclude_list or []
		src_df_mapped = self._exclude_columns(src_df_mapped, exclude)
		trg_df_mapped = self._exclude_columns(trg_df_mapped, exclude)

		columns_result = self.compare_columns(src_df_mapped, trg_df_mapped)
		data_result = self.compare_full_data(src_df_mapped, trg_df_mapped, columns_result)

		return DataCheckResult(
			dataset_name=dataset_name,
			src_count=src_count,
			trg_count=trg_count,
			row_count_passed=row_count_passed,
			columns=columns_result,
			data=data_result,
		)

class ReportGenerator:
	def __init__(self, debug: int = 0) -> None:
		self.debug = debug

	@staticmethod
	def _compute_status(rows_count: str, columns: str, data: str) -> str:
		values = [rows_count, columns, data]
		if columns == NULL_TAG or data == NULL_TAG:
			return ERROR_TAG
		if all(value == PASS_TAG for value in values):
			return PASS_TAG
		if any(value == ERROR_TAG for value in values):
			return ERROR_TAG
		return FAIL_TAG

	def print_dataset_report(self, result: DataCheckResult) -> None:
		print(f"\n=== {result.dataset_name} ===")
		if result.error_message:
			print(f"error_message: {result.error_message}")
			print(f"row_count_check: {ERROR_TAG}")
			print(f"column_name_consistency: {ERROR_TAG}")
			print(f"full_data_verification: {ERROR_TAG}")
			return

		skipping_both_empty = result.data.reason == "Skipping due to both datasets empty"
		skipping_one_empty = result.data.reason == "Skipping due to one dataset empty"

		if skipping_both_empty:
			print("error_message: there is no data for comparison")
			print(f"row_count_check: {NULL_TAG} (src={result.src_count}, trg={result.trg_count})")
		else:
			print(f"row_count_check: {PASS_TAG if result.row_count_passed else FAIL_TAG} (src={result.src_count}, trg={result.trg_count})")

		if skipping_both_empty:
			print("column_name_consistency: NULL")
		elif skipping_one_empty:
			print("column_name_consistency: FAIL (Skipping)")
		else:
			print(
				"column_name_consistency: "
				f"{PASS_TAG if result.columns.passed else FAIL_TAG} "
				f"(same_order={result.columns.same_order})"
			)

		if not (skipping_both_empty or skipping_one_empty) and not result.columns.passed:
			print(f"  missing_in_trg: {result.columns.missing_in_trg}")
			print(f"  missing_in_src: {result.columns.missing_in_src}")

		if skipping_both_empty:
			print("full_data_verification: NULL")
		elif skipping_one_empty:
			print("full_data_verification: FAIL (Skipping)")
		else:
			print(f"full_data_verification: {PASS_TAG if result.data.passed else FAIL_TAG} ({result.data.reason})")

		if not (skipping_both_empty or skipping_one_empty) and not result.data.passed and result.data.src_only_count is not None:
			print(f"  src_only_rows: {result.data.src_only_count}")
			print(f"  trg_only_rows: {result.data.trg_only_count}")

			if self.debug > 0 and result.data.src_only_sample:
				print("  \nsrc_only_sample:")
				for row in result.data.src_only_sample:
					print(f"    {row}")

			if self.debug > 0 and result.data.trg_only_sample:
				print("  \ntrg_only_sample:")
				for row in result.data.trg_only_sample:
					print(f"    {row}")

	def build_summary_rows(self, results: list[DataCheckResult]) -> list[dict[str, str]]:
		rows = []
		for result in results:
			if result.error_message:
				status = self._compute_status(ERROR_TAG, ERROR_TAG, ERROR_TAG)
				rows.append(
					{
						"name": result.dataset_name,
						"rows_count": ERROR_TAG,
						"columns": ERROR_TAG,
						"data": ERROR_TAG,
						"status": status,
					}
				)
				continue

			if result.data.reason == "Skipping due to both datasets empty":
				rows_count = NULL_TAG
				columns = NULL_TAG
				data = NULL_TAG
				status = self._compute_status(rows_count, columns, data)
				rows.append(
					{
						"name": result.dataset_name,
						"rows_count": rows_count,
						"columns": columns,
						"data": data,
						"status": status,
					}
				)
				continue

			rows_count = PASS_TAG if result.row_count_passed else FAIL_TAG
			columns = PASS_TAG if result.columns.passed else FAIL_TAG
			data = PASS_TAG if result.data.passed else FAIL_TAG
			status = self._compute_status(rows_count, columns, data)

			rows.append(
				{
					"name": result.dataset_name,
					"rows_count": rows_count,
					"columns": columns,
					"data": data,
					"status": status,
				}
			)
		return rows

	def render_summary_text(self, rows: list[dict[str, str]], title: str) -> str:
		headers = ["Name", "Row Count", "Columns", "Data Check", "Status"]
		keys = ["name", "rows_count", "columns", "data", "status"]
		min_widths = [27, 12, 9, 12, 8]

		widths = []
		for index, (header, key) in enumerate(zip(headers, keys)):
			max_value_len = max((len(str(row[key])) for row in rows), default=0)
			widths.append(max(len(header), max_value_len, min_widths[index]))

		def format_line(values: list[str]) -> str:
			cells = []
			for index, (value, width) in enumerate(zip(values, widths)):
				text = str(value)
				if index == 0:
					cells.append(text.ljust(width))
				else:
					cells.append(text.center(width))
			return " | ".join(cells)

		separator = "-+-".join("-" * width for width in widths)

		total_passed = sum(1 for row in rows if row["status"] == PASS_TAG)
		total_error = sum(1 for row in rows if row["status"] == ERROR_TAG)
		total_failed = sum(1 for row in rows if row["status"] == FAIL_TAG)

		lines = []
		lines.append(f"=== {title} ===")
		lines.append(separator)
		lines.append(format_line(headers))
		lines.append(separator)
		for row in rows:
			lines.append(format_line([row["name"], row["rows_count"], row["columns"], row["data"], row["status"]]))
		lines.append(separator)
		lines.append("")
		lines.append(f"Total Passed: {total_passed}")
		lines.append(f"Total Failed: {total_failed}")
		lines.append(f"Total Errors: {total_error}")

		return "\n".join(lines)

	def print_final_summary(self, rows: list[dict[str, str]]) -> None:
		print("\n" + self.render_summary_text(rows, title="Check Results"))


class ReportWriter:
	def __init__(self, base_dir: Path, report_generator: ReportGenerator) -> None:
		self.base_dir = base_dir
		self.report_generator = report_generator

	def write_final_summary_report(self, rows: list[dict[str, str]], check_list_name: str) -> Path:
		report_dir = self.base_dir / "report"
		report_dir.mkdir(parents=True, exist_ok=True)
		timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
		report_file = report_dir / f"final_report_{timestamp}.txt"
		report_text = self.report_generator.render_summary_text(rows, title=f"Check list: {check_list_name}")
		report_file.write_text(report_text + "\n", encoding="utf-8")
		return report_file


class InitApplication:
	def __init__(self, base_dir: Path) -> None:
		self.base_dir = base_dir
		self.config_loader = ConfigLoader(base_dir / "config.yaml")
		self.validator = DataValidator()
		self.report_generator = ReportGenerator(debug=0)
		self.report_writer = ReportWriter(base_dir, self.report_generator)

	def run(self) -> None:
		config = self.config_loader.load()
		self.report_generator.debug = config.debug
		self.validator.sample_diff_rows = config.sample_diff_rows
		data_loader = DataLoader(self.base_dir, config.data_dir)

		print("Data comparison started")
		print(f"Check list: {config.check_list_name}")
		print(f"Data sets to compare: {len(config.data_list)}")

		results: list[DataCheckResult] = []
		for dataset_name in config.data_list:
			error_message = data_loader.check_data_files(dataset_name)

			if error_message is None:
				src_df = data_loader.load_dataset_dataframe("src", dataset_name)
				trg_df = data_loader.load_dataset_dataframe("trg", dataset_name)
				dataset_mapping = config.mapping_fields.get(dataset_name, {})
				dataset_exclude = config.exclude_fields.get(dataset_name, [])
				result = self.validator.validate_dataset(dataset_name, src_df, trg_df, dataset_mapping, dataset_exclude)
			else:
				result = self.validator.build_error_result(dataset_name, error_message)

			results.append(result)
			self.report_generator.print_dataset_report(result)

		summary_rows = self.report_generator.build_summary_rows(results)
		self.report_generator.print_final_summary(summary_rows)

		report_file = self.report_writer.write_final_summary_report(summary_rows, config.check_list_name)
		print(f"\nReport written to: {report_file}")


def main() -> None:
	base_dir = Path(__file__).resolve().parent
	app = InitApplication(base_dir)
	app.run()


if __name__ == "__main__":
	main()
