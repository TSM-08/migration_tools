# Migration Data Check App

This project compares source and target JSON datasets and generates a text report with check results.

It also includes a loader that connects to source and target databases, validates connectivity, and exports configured datasets to JSON files.

## Prerequisites

- Python 3.12+
- Windows Command Prompt (CMD) or PowerShell

## Project Structure

- `app_checks.py`: main application
- `app_loader.py`: database connectivity check + JSON data export (`src` and `trg`)
- `config.yaml`: runtime configuration
- `connection.yaml`: database connection configuration
- `requirements.txt`: Python dependencies
- `data/src` and `data/trg`: input JSON files
- `report`: generated reports

## 1. Prepare Environment

### Windows Command Prompt (CMD)

```bat
cd /d C:\Projects\migration
python -m venv .venv
.venv\Scripts\activate.bat
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

### Windows PowerShell

```powershell
cd C:\Projects\migration
python -m venv .venv
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

### Verify Installation

```bat
python -m pip show pandas pyyaml
```

## 2. Configure the App

Edit `config.yaml` and set:

- `data_checks.data_dir`: data folder (default: `data`)
- `run_mode.check_list`: list to run (example: `view_list` or `data_list`)
- `run_mode.debug`: set to `1` to print sample mismatch rows
- `run_mode.sample_diff_rows`: number of mismatch rows to include in samples

Example:

```yaml
data_checks:
  data_dir: "data"
  data_list:
    - "nsa_v_feeds"
  view_list:
    - "nsa_v_all_sc_ref_grouped"
    - "nsa_v_feeds"

run_mode:
  check_list: "view_list"
  debug: 0
  sample_diff_rows: 5
```

## 3. Run the App

```bat
python app_checks.py
```

## 3a. Load Data From DB (app_loader.py)

`app_loader.py` runs in two steps:

1. Tests both configured connections (`src`, `trg`) from `connection.yaml`.
2. If both pass, loads views listed in `config.yaml` at `run_mode.check_list` and writes JSON files.

### What it reads

- `config.yaml`:
  - `run_mode.check_list` (for example `view_list`)
  - `data_checks.<check_list_name>` (list of views/datasets to extract)
  - `data_checks.data_dir` (output root, usually `data`)
- `connection.yaml`:
  - `connections.src`
  - `connections.trg`

### Output files

For each dataset name, the loader writes:

- `<data_dir>/src/<dataset>.json`
- `<data_dir>/trg/<dataset>.json`

Example (with `data_dir: data`):

- `data/src/nsa_v_feeds.json`
- `data/trg/nsa_v_feeds.json`

Run it:

```bat
python app_loader.py
```

## 4. Output

- Console output: per-view checks and summary table
- File output: report file in `report/final_report_YYYYMMDD_HHMMSS.txt`
- Loader output: JSON files in `<data_checks.data_dir>/src` and `<data_checks.data_dir>/trg`

## 5. Troubleshooting

### Missing dependency error

```bat
python -m pip install -r requirements.txt
```

### Wrong interpreter in VS Code

Select the interpreter from:

- `.venv\Scripts\python.exe`

### Regenerate environment

```bat
deactivate
rmdir /s /q .venv
python -m venv .venv
.venv\Scripts\activate.bat
python -m pip install -r requirements.txt
```

### Regenerate environment (PowerShell)

```powershell
Deactivate
Remove-Item -Recurse -Force .venv
python -m venv .venv
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```
