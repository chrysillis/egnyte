#!/bin/sh
echo "Enter the company's Egnyte domain:"
read domain
echo "Enter your domain username:"
read name
echo "Enter the name of the drive you want to map:"
read label
echo "Enter the drive path you want to map (/shared/drive):"
read drive
egnytecli drives add $label --domain $domain --username $name --cloudStartPath $drive --openSession