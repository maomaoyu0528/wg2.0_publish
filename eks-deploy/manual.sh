#!/bin/bash

clustername="${1?Please provide the cluster name}"
region="${2?Please provide the region}"
profile="${3:-default}"

for file in $(find . -type f -name "*.tpl" -print)
do
    new_file="${file%.tpl}"

    content=$(cat "$file" | sed "s/{{clustername}}/$clustername/g" | sed "s/{{region}}/$region/g" | sed "s/{{profile}}/$profile/g")

    echo "$content" > "$new_file"   
done