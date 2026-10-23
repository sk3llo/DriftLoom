`*.zip` files in this folder are DriftLoom database exports, in all possible configurations:
- `db` / `nodb` indicates if there is a `driftloom.db` database included or not
- `ser` / `vulnser` / `noser` indicates if there is a `driftloom.settings` Java-serialized preferences file included, if it is included and contains an injection attack, of if it is not included
- `json` / `nojson` indicates if there is a `preferences.json` JSON preferences file included or not
