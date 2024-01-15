# azure_sustainability_data

![workflow](https://github.com/autosysops/azure_sustainability_data/actions/workflows/run.yml/badge.svg)

This repository contains a workflow to daily check the data in [Azure Globe](https://datacenters.microsoft.com/globe/) concerning sustainability. It parses the fact sheets provided by Microsoft and compiles the data in a json file which can be found in this repository.

When changes are done a pull request will be made and after a check it will be merged to make sure the data is as current as possible. Do note that not all azure regions have a fact sheet (yet) so it will only show the ones which have a fact sheet here.

If you have any suggestions for data to add or how to format the data better feel free to make an issue or pull request. Feel free to refer to the raw data file in this repository if you need to use this data.
