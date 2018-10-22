ballerina build order-signal-data-service
docker build -t rajkumar/order-signal-data-service:0.1.0 -f order-signal-data-service/docker/Dockerfile .
docker push rajkumar/order-signal-data-service:0.1.0
kubectl delete -f order-signal-data-service/kubernetes/order_signal_data_service_deployment.yaml
kubectl create -f order-signal-data-service/kubernetes/order_signal_data_service_deployment.yaml
kubectl create -f order-signal-data-service/kubernetes/order_signal_data_service_svc.yaml