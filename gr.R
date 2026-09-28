# geo-report-gen command-line entry point. Run from the project root:
#   Rscript gr.R help
source(file.path("R", "load.R"))
gr_main(commandArgs(trailingOnly = TRUE))
