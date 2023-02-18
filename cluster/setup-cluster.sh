
echo "Setting kibana_system password";
until curl -s -X POST -u elastic:${ELASTIC_PASSWORD} -H "Content-Type: application/json" https://es-cluster-01:9200/_security/user/kibana_system/_password -d "{\"password\":\"${KIBANA_PASSWORD}\"}" | grep -q "^{}"; do sleep 10; done;
echo "All done!";