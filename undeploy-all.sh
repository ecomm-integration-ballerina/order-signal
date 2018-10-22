kubectl delete -f order-signal-data-service/kubernetes/order_signal_data_service_deployment.yaml
kubectl delete -f order-signal-inbound-dispatcher/kubernetes/order_signal_inbound_dispatcher_deployment.yaml
kubectl delete -f order-signal-inbound-processor/kubernetes/order_signal_inbound_processor_deployment.yaml
kubectl delete -f order-signal-outbound/kubernetes/order_signal_outbound_deployment.yaml