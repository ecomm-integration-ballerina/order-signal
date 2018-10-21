FROM ballerina/ballerina:0.982.0
LABEL maintainer="rajkumarr@wso2.com"

COPY target/order-signal-data-service.balx /home/ballerina
COPY order-signal-data-service/conf/ballerina.conf /home/ballerina

COPY order-signal-data-service/dependencies/packages/dependencies/* /ballerina/runtime/bre/lib/

EXPOSE  8280
EXPOSE  9797

CMD ballerina run order-signal-data-service.balx