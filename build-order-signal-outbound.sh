ballerina build order-signal-outbound
docker build -t rajkumar/order-signal-outbound:0.1.0 -f order-signal-outbound/docker/Dockerfile .
docker push rajkumar/order-signal-outbound:0.1.0
kubectl delete -f order-signal-outbound/kubernetes/order_signal_outbound_deployment.yaml
kubectl create -f order-signal-outbound/kubernetes/order_signal_outbound_deployment.yaml