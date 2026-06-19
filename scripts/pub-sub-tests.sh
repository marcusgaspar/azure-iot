#!/bin/bash
kubectl run mqtt-sub --rm -it --restart=Never -n azure-iot-operations \
  --image=eclipse-mosquitto -- \
  mosquitto_sub -h demo1883.azure-iot-operations.svc.cluster.local -p 1883 -t "video-analytics/detections" -v

kubectl delete pod mqtt-sub -n azure-iot-operations --ignore-not-found

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
