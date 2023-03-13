#!/bin/bash

# we have admin password hard coded as "password" in the external secrets manifest (in bootstrap)
valuesPassword="password"
valuesPasswordHash=$(echo -n "$valuesPassword" | shasum -a 256 | awk '{ print $1 }' | tr -d '\n')

while ! kubectl get secret --namespace loft loft-user-secret-admin > /dev/null 2>&1; do
	echo "waiting for loft admin user secret to be created..."
	sleep 1
done

secretsPasswordHash=$(kubectl get secrets --namespace loft loft-user-secret-admin -o jsonpath='{.data.password}' | base64 -d)

if [ "$valuesPasswordHash" == "$secretsPasswordHash" ];
then
	echo "$valuesPassword";
else
	echo "unknown, password hashes do not match"
fi;
