#!/bin/bash
kubectl create namespace azure-iot-operations

# Cria uma vez (fica rodando, ocioso)
kubectl run mqtt-tester -n azure-iot-operations \
  --image=eclipse-mosquitto --restart=Never \
  --command -- sleep infinity

# Espera ficar Ready
kubectl wait --for=condition=Ready pod/mqtt-tester -n azure-iot-operations --timeout=30s

# Agora reexecuta o subscribe quantas vezes quiser (Ctrl+C sai sem matar o pod)
kubectl exec -it mqtt-tester -n azure-iot-operations -- \
  mosquitto_sub -h 10.20.0.4 -p 1883 -t "video-analytics/detections/edge-device-01" -v

kubectl delete pod mqtt-tester -n azure-iot-operations

kubectl delete pod mqtt-sub -n azure-iot-operations --ignore-not-found

kubectl run mqtt-sub --rm -it --restart=Never -n azure-iot-operations \
  --image=eclipse-mosquitto -- \
  mosquitto_sub -h demo1883.azure-iot-operations.svc.cluster.local -p 1883 -t "video-analytics/detections" -v

kubectl run mqtt-sub --rm -it --restart=Never -n azure-iot-operations \
  --image=eclipse-mosquitto -- \
  mosquitto_sub -h 10.20.0.4 -p 1883 -t "video-analytics/detections/edge-device-02" -v



kubectl run mqtt-sub --rm -it --restart=Never -n azure-iot-operations \
  --image=eclipse-mosquitto -- \
  mosquitto_sub -h demo1883.azure-iot-operations.svc.cluster.local -p 1883 -t "azure-iot-operations/data/#" -v

mosquitto_pub \
  --host aio-broker \
  --port 18883 \
  --message "hello 4444" \
  --topic "world" \
  --debug \
  --cafile /var/run/certs/ca.crt \
  -D CONNECT authentication-method 'K8S-SAT' \
  -D CONNECT authentication-data $(cat /var/run/secrets/tokens/broker-sat)

mosquitto_sub \
  --host aio-broker \
  --port 18883 \
  --topic "teste" \
  --debug \
  --cafile /var/run/certs/ca.crt \
  -D CONNECT authentication-method 'K8S-SAT' \
  -D CONNECT authentication-data $(cat /var/run/secrets/tokens/broker-sat)


# Docker mqtt app https://mqttx.app/docs/cli/downloading-and-installation#linux
docker run -it --rm emqx/mqttx-cli
mqttx conn -h 10.20.0.4 -p 1883

# https://mqttx.app/docs/cli/get-started
# Subscribe
mqttx sub -t 'hello' -h 'broker.emqx.io' -p 1883

# Publish a single message
mqttx pub -t 'hello' -h 'broker.emqx.io' -p 1883 -m 'from MQTTX CLI'
# Publish multiple messages (multiline)
mqttx pub -t 'hello' -h 'broker.emqx.io' -p 1883 -lm
# Publish a random payload of specified size
mqttx pub -t 'hello' -h 'broker.emqx.io' -p 1883 --payload-size 1KB

#❯ docker run -it --rm emqx/mqttx-cli
#/app # mqttx conn -h broker.emqx.io -p 1883
#✔ Connected
#- Press Ctrl+C to disconnect and exit