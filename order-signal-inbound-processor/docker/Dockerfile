FROM ballerina/ballerina:0.982.0
LABEL maintainer="rajkumarr@wso2.com"

COPY target/order-signal-inbound-processor.balx /home/ballerina
COPY order-signal-inbound-processor/conf/ballerina.conf /home/ballerina

COPY order-signal-inbound-processor/dependencies/packages/dependencies/* /ballerina/runtime/bre/lib/
COPY order-signal-inbound-processor/dependencies/packages/balo/* /ballerina/runtime/lib/repo/

CMD ballerina run order-signal-inbound-processor.balx
