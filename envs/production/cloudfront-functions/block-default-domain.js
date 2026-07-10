// Rejects any request whose Host header isn't the custom domain. Without
// this, the same site is fully reachable at the default *.cloudfront.net
// domain (AWS never lets you disable it) — this makes that domain
// effectively dead, matching the ALB's security-group-based lockdown.
function handler(event) {
  var request = event.request;
  var host = request.headers.host && request.headers.host.value;

  if (host !== "app.tamci.app") {
    return {
      statusCode: 403,
      statusDescription: "Forbidden",
      body: {
        encoding: "text",
        data: "Forbidden",
      },
    };
  }

  return request;
}
