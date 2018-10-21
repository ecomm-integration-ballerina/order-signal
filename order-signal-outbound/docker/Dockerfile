FROM ballerina/ballerina:0.982.0
LABEL maintainer="rajkumarr@wso2.com"

COPY target/order-signal-outbound.balx /home/ballerina
COPY order-signal-outbound/conf/ballerina.conf /home/ballerina

CMD ballerina run order-signal-outbound.balx
