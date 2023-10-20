#!/usr/bin/env bash

base=`dirname "${0}"`

if [ -d "${base}/../cert" ]
then
  if [ -f "${base}/../cert/fullchain.pem" ]
  then
    cert_date=`date -r "${base}/../cert/fullchain.pem" +%s`
    now=`date +%s`
    cert_age=$(( now - cert_date ))
    unset cert_date now
    if (( cert_age > 3600 * 24 * 85 ))
    then
      echo '[33mTLS certificates will expire in less than 5 days[m'
    elif (( cert_age > 3600 * 24 * 80 ))
    then
      echo '[33mTLS certificates will expire in less than 10 days[m'
    elif (( cert_age > 3600 * 24 * 75 ))
    then
      echo '[33mTLS certificates will expire in less than 15 days[m'
    elif (( cert_age > 3600 * 24 * 70 ))
    then
      echo '[33mTLS certificates will expire in less than 20 days[m'
    fi
  else
    echo "[31mCould not find[37m ${base}/../cert/fullchain.pem[m"
  fi
else
  echo "[31mCould not find[37m ${base}/../cert[m"
fi
