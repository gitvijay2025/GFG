# Code Citations

## License: MIT
https://github.com/awsrun/aws-microservices/blob/905ae57cb6dddcec23fc2f7a01feef0565df8e60/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body = await checkoutBasket(event)
```


## License: unknown
https://github.com/jamessonfaria/aws-microservices-ecommerce/blob/8fd1ae669ecdb5b38f782050e6473c0a27fc4a67/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body = await checkoutBasket(event)
```


## License: unknown
https://github.com/RomanMart/aws-microservices/blob/10c6ebd35b7feb5000ef0fae2f78d3e91094a4aa/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body = await checkoutBasket(event)
```


## License: MIT
https://github.com/awsrun/aws-microservices/blob/905ae57cb6dddcec23fc2f7a01feef0565df8e60/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body = await checkoutBasket(event); // POST /basket/checkout
          } else {
            body = await
```


## License: unknown
https://github.com/jamessonfaria/aws-microservices-ecommerce/blob/8fd1ae669ecdb5b38f782050e6473c0a27fc4a67/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body = await checkoutBasket(event); // POST /basket/checkout
          } else {
            body = await
```


## License: unknown
https://github.com/enriquecordero/rest_api_cdk/blob/92000dbf6f91f7f96e8161f5c5951b4fa5d100b5/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body = await checkoutBasket(event); // POST /basket/checkout
          } else {
            body = await
```


## License: unknown
https://github.com/RomanMart/aws-microservices/blob/10c6ebd35b7feb5000ef0fae2f78d3e91094a4aa/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body = await checkoutBasket(event); // POST /basket/checkout
          } else {
            body = await
```


## License: MIT
https://github.com/awsrun/aws-microservices/blob/905ae57cb6dddcec23fc2f7a01feef0565df8e60/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body = await checkoutBasket(event); // POST /basket/checkout
          } else {
            body = await createBasket(event); // POST /basket
          }
          break;
        case "DELETE":
          body = await deleteBasket(event.pathParameters.userName); // DELETE /basket/{userName
```


## License: unknown
https://github.com/jamessonfaria/aws-microservices-ecommerce/blob/8fd1ae669ecdb5b38f782050e6473c0a27fc4a67/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body = await checkoutBasket(event); // POST /basket/checkout
          } else {
            body = await createBasket(event); // POST /basket
          }
          break;
        case "DELETE":
          body = await deleteBasket(event.pathParameters.userName); // DELETE /basket/{userName
```


## License: unknown
https://github.com/enriquecordero/rest_api_cdk/blob/92000dbf6f91f7f96e8161f5c5951b4fa5d100b5/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body = await checkoutBasket(event); // POST /basket/checkout
          } else {
            body = await createBasket(event); // POST /basket
          }
          break;
        case "DELETE":
          body = await deleteBasket(event.pathParameters.userName); // DELETE /basket/{userName
```


## License: unknown
https://github.com/RomanMart/aws-microservices/blob/10c6ebd35b7feb5000ef0fae2f78d3e91094a4aa/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body = await checkoutBasket(event); // POST /basket/checkout
          } else {
            body = await createBasket(event); // POST /basket
          }
          break;
        case "DELETE":
          body = await deleteBasket(event.pathParameters.userName); // DELETE /basket/{userName
```


## License: unknown
https://github.com/jamessonfaria/aws-microservices-ecommerce/blob/8fd1ae669ecdb5b38f782050e6473c0a27fc4a67/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body =
```


## License: unknown
https://github.com/enriquecordero/rest_api_cdk/blob/92000dbf6f91f7f96e8161f5c5951b4fa5d100b5/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body =
```


## License: unknown
https://github.com/RomanMart/aws-microservices/blob/10c6ebd35b7feb5000ef0fae2f78d3e91094a4aa/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body =
```


## License: MIT
https://github.com/awsrun/aws-microservices/blob/905ae57cb6dddcec23fc2f7a01feef0565df8e60/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body =
```


## License: MIT
https://github.com/awsrun/aws-microservices/blob/905ae57cb6dddcec23fc2f7a01feef0565df8e60/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body = await checkoutBasket(event); // POST /basket/checkout
          } else {
            body = await createBasket(event); // POST /basket
          }
          break;
        case "DELETE":
          body = await deleteBasket(event.pathParameters.userName); // DELETE /basket/{userName}
          break;
        default:
          throw new Error(`Unsupported route
```


## License: unknown
https://github.com/jamessonfaria/aws-microservices-ecommerce/blob/8fd1ae669ecdb5b38f782050e6473c0a27fc4a67/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body = await checkoutBasket(event); // POST /basket/checkout
          } else {
            body = await createBasket(event); // POST /basket
          }
          break;
        case "DELETE":
          body = await deleteBasket(event.pathParameters.userName); // DELETE /basket/{userName}
          break;
        default:
          throw new Error(`Unsupported route
```


## License: unknown
https://github.com/enriquecordero/rest_api_cdk/blob/92000dbf6f91f7f96e8161f5c5951b4fa5d100b5/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body = await checkoutBasket(event); // POST /basket/checkout
          } else {
            body = await createBasket(event); // POST /basket
          }
          break;
        case "DELETE":
          body = await deleteBasket(event.pathParameters.userName); // DELETE /basket/{userName}
          break;
        default:
          throw new Error(`Unsupported route
```


## License: unknown
https://github.com/RomanMart/aws-microservices/blob/10c6ebd35b7feb5000ef0fae2f78d3e91094a4aa/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body = await checkoutBasket(event); // POST /basket/checkout
          } else {
            body = await createBasket(event); // POST /basket
          }
          break;
        case "DELETE":
          body = await deleteBasket(event.pathParameters.userName); // DELETE /basket/{userName}
          break;
        default:
          throw new Error(`Unsupported route
```


## License: MIT
https://github.com/awsrun/aws-microservices/blob/905ae57cb6dddcec23fc2f7a01feef0565df8e60/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body = await checkoutBasket(event); // POST /basket/checkout
          } else {
            body = await createBasket(event); // POST /basket
          }
          break;
        case "DELETE":
          body = await deleteBasket(event.pathParameters.userName); // DELETE /basket/{userName}
          break;
        default:
          throw new Error(`Unsupported route: "${event.httpMethod
```


## License: unknown
https://github.com/jamessonfaria/aws-microservices-ecommerce/blob/8fd1ae669ecdb5b38f782050e6473c0a27fc4a67/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body = await checkoutBasket(event); // POST /basket/checkout
          } else {
            body = await createBasket(event); // POST /basket
          }
          break;
        case "DELETE":
          body = await deleteBasket(event.pathParameters.userName); // DELETE /basket/{userName}
          break;
        default:
          throw new Error(`Unsupported route: "${event.httpMethod
```


## License: unknown
https://github.com/enriquecordero/rest_api_cdk/blob/92000dbf6f91f7f96e8161f5c5951b4fa5d100b5/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body = await checkoutBasket(event); // POST /basket/checkout
          } else {
            body = await createBasket(event); // POST /basket
          }
          break;
        case "DELETE":
          body = await deleteBasket(event.pathParameters.userName); // DELETE /basket/{userName}
          break;
        default:
          throw new Error(`Unsupported route: "${event.httpMethod
```


## License: unknown
https://github.com/RomanMart/aws-microservices/blob/10c6ebd35b7feb5000ef0fae2f78d3e91094a4aa/src/basket/index.js

```
async function(event) {
    console.log("request:", JSON.stringify(event, undefined, 2));

    let body;

    try {
      switch (event.httpMethod) {
        case "GET":
          if (event.pathParameters != null) {
            body = await getBasket(event.pathParameters.userName); // GET /basket/{userName}
          } else {
            body = await getAllBaskets(); // GET /basket
          }
          break;
        case "POST":
          if (event.path === "/basket/checkout") {
            body = await checkoutBasket(event); // POST /basket/checkout
          } else {
            body = await createBasket(event); // POST /basket
          }
          break;
        case "DELETE":
          body = await deleteBasket(event.pathParameters.userName); // DELETE /basket/{userName}
          break;
        default:
          throw new Error(`Unsupported route: "${event.httpMethod
```

