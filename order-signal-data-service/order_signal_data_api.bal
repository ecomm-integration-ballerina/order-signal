import ballerina/http;
import ballerina/log;
import ballerina/mysql;
import raj/orders.signal.model as model;

endpoint http:Listener orderSignalListener {
    port: 8280
};

@http:ServiceConfig {
    basePath: "/data/order-signal"
}
service<http:Service> orderSignalAPI bind orderSignalListener {

    @http:ResourceConfig {
        methods:["GET"],
        path: "/healthz"
    }
    healthz (endpoint outboundEp, http:Request req) {
        http:Response res = new;
        res.setJsonPayload({"message": "I'm still alive!"}, contentType = "application/json");
        outboundEp->respond(res) but { error e => log:printError("Error while responding", err = e) };
    } 
    
    @http:ResourceConfig {
        methods:["POST"],
        path: "/",
        body: "orderSignal"
    }
    addOrderSignal (endpoint outboundEp, http:Request req, model:OrderSignalDAO orderSignal) {
        http:Response res = addOrderSignal(req, untaint orderSignal);
        outboundEp->respond(res) but { error e => log:printError("Error while responding", err = e) };
    }

    @http:ResourceConfig {
        methods:["GET"],
        path: "/"
    }
    getOrderSignals (endpoint outboundEp, http:Request req) {
        http:Response res = getOrderSignals(untaint req);
        outboundEp->respond(res) but { error e => log:printError("Error while responding", err = e) };
    }

    @http:ResourceConfig {
        methods:["PUT"],
        path: "/process-flag/",
        body: "orderSignal"
    }
    updateProcessFlag (endpoint outboundEp, http:Request req, model:OrderSignalDAO orderSignal) {
        http:Response res = updateProcessFlag(req, untaint orderSignal);
        outboundEp->respond(res) but { error e => log:printError("Error while responding", err = e) };
    }

    @http:ResourceConfig {
        methods:["PUT"],
        path: "/process-flag/batch/",
        body: "orderSignals"
    }
    batchUpdateProcessFlag (endpoint outboundEp, http:Request req, model:OrderSignalsDAO orderSignals) {
        http:Response res = batchUpdateProcessFlag(req, orderSignals);
        outboundEp->respond(res) but { error e => log:printError("Error while responding", err = e) };
    }
}