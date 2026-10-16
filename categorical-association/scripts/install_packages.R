# Install the R packages this Skill needs (run once): Rscript install_packages.R
pkgs <- c("jsonlite", "readr", "readxl", "ggplot2", "scales", "PropCIs")
missing <- setdiff(pkgs, rownames(installed.packages()))
if (length(missing) > 0) install.packages(missing, repos = "https://cloud.r-project.org")
message("OK: ", paste(pkgs, collapse = ", "))
