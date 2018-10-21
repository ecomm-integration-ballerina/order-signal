FROM ballerina/ballerina:0.982.0
LABEL maintainer="rajkumarr@wso2.com"

COPY target/order-signal-inbound-dispatcher.balx /home/ballerina
COPY order-signal-inbound-dispatcher/conf/ballerina.conf /home/ballerina

COPY order-signal-inbound-dispatcher/dependencies/packages/dependencies/* /ballerina/runtime/bre/lib/
COPY order-signal-inbound-dispatcher/dependencies/packages/balo/* /ballerina/runtime/lib/repo/

CMD ballerina run order-signal-inbound-dispatcher.balx
