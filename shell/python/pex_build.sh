#!/bin/bash

# fail fast
set -e

# ensure we exit out of any current virtualenv
deactivate || true

# clear down last pex build history
rm -rf ~/.pex

# platform
platform="linux"

# architecture
arch="64"

# python version
python_version="2"

# friendly app name
app_name="MovieGrabber"

# name of requirements file (contains list of required python packages generated by pycharm)
requirements_file="requirements.txt"

# path to requirements file
requirements_path="/tmp"

# pex output path
pex_output_path="/tmp/venv"

# generate path for virtualenv
venv_path="/tmp/venv"

# python app name
pex_output_file="${app_name}-${platform}${arch}"

# remove previous pex package
rm -rf "${pex_output_path}/${pex_output_file}.pex"

# run virtualenv
virtualenv -p "python${python_version}" "${venv_path}"

# activate new virtualenv environment (gives you access to pip in virtual env)
source "${venv_path}/bin/activate"

# pip install pex
"${venv_path}/bin/pip" install pex

# create pex requirements package for application
pex -r "${requirements_path}/${requirements_file}" -o "${pex_output_path}/${pex_output_file}.pex"

# ensure we are now exit current venv
deactivate || true

echo "Now use the pex package by executing '${pex_output_path}/${pex_output_file}.pex ./${pex_output_file}.py'"