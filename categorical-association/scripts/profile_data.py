# Stage 1 without R (claude.ai): same output as profile_data.R.
#
# Usage: python profile_data.py <data file> <output dir>
# Writes <output dir>/profile.json and 資料總覽_<data>.md. Every guess must be confirmed with the user.

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cda_describe as cd  # noqa: E402

if len(sys.argv) != 3:
    sys.exit("Usage: python profile_data.py <data file> <output dir>")
data_file, out_dir = sys.argv[1], sys.argv[2]
os.makedirs(out_dir, exist_ok=True)
out_file = os.path.join(out_dir, "profile.json")

try:
    data = cd.read_data(data_file)
except Exception as e:  # report in the same place as the R script
    cd.write_json({"error": "無法讀取資料： %s" % e}, out_file)
    sys.exit("ERROR: %s" % e)

profile = cd.cda_profile(data)
profile["file"] = os.path.abspath(data_file).replace("\\", "/")
cd.write_json(profile, out_file)

overview_file = os.path.join(out_dir, "資料總覽_%s.md" % cd.data_stem(data_file))
cd.write_lines(cd.overview_md(data, profile, os.path.basename(data_file)), overview_file)
print("OK:", os.path.abspath(out_file))
print("OK:", os.path.abspath(overview_file))
