import ballerina/test;
import ballerina/io;
import ballerina/http;

function startService() {
}

@test:Config {
    before: "startService",
    after: "stopService"
}
function testFunc() {

    endpoint http:Client httpEndpoint { url: "http://localhost:9090" ,
        followRedirects: { enabled: true, maxCount: 5 }};
    // Check whether the server is started
    //test:assertTrue(serviceStarted, msg = "Unable to start the service");

    string response1 = "Hello World!";

    // Send a GET request to the specified endpoint
    var response = httpEndpoint->get("/redirect1");
    match response {
        http:Response resp => {
            var res = check resp.getTextPayload();
            test:assertEquals(res, response1);
        }
        error err => test:assertFail(msg = "Failed to call the endpoint:");
    }
}

function stopService() {
}