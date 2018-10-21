ballerina build order-signal-inbound-dispatcher
docker build -t rajkumar/order-signal-inbound-dispatcher:0.1.0 -f order-signal-inbound-dispatcher/docker/Dockerfile .
docker push rajkumar/order-signal-inbound-dispatcher:0.1.0
kubectl delete -f order-signal-inbound-dispatcher/kubernetes/order_signal_inbound_dispatcher_deployment.yaml
kubectl create -f order-signal-inbound-dispatcher/kubernetes/order_signal_inbound_dispatcher_deployment.yaml