# TODO
The highest priority items will be addressed in April. After that, the LaTeX paper will be the focus throughout the month of May (while the captures run in scale). Lower priority items will be addressed in late June and beyond.

### Now
* Provision instances in all the planned regions (also, it is a good opportunity to split/refactor/modularize Terraform files).
* Improve resource and variable naming.
* Make everything more parametrized and abstract. Avoid hardcoding/hardwiring things.
* Improve tcpdump filter syntax/semantics in order to make it more elegant and readable at scale/long term.
* Ensure that the 8GB of disk space would not eventually be exceeded by the same given capture rotation. Give the instances more disk space and plan a runtime mitigation. Considering only a single rotation file, as each rotation removes files after uploading them to S3.

### Late June and beyond
* Use OpenRC to wrap my own scripts as supervised daemons, rather than running directly from the shell as in the last 3 lines of code of the startup_script.sh file.
* Develop the honeypot solutions.
* Expand to Azure.