ballerina build order-signal-inbound-processor
docker build -t rajkumar/order-signal-inbound-processor:0.1.0 -f order-signal-inbound-processor/docker/Dockerfile .
docker push rajkumar/order-signal-inbound-processor:0.1.0
kubectl delete -f order-signal-inbound-processor/kubernetes/order_signal_inbound_processor_deployment.yaml
kubectl create -f order-signal-inbound-processor/kubernetes/order_signal_inbound_processor_deployment.yaml