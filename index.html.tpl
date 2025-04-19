<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8"/>
  <title>My AWS SPA</title>
</head>
<body>
  <h1>Welcome to my AWS‑hosted SPA</h1>
  <button id="sayHello">Say Hello</button>
  <p id="msg"></p>

  <script>
    document.getElementById('sayHello').addEventListener('click', () => {
      fetch("{{API_URL}}")
        .then(res => res.text())
        .then(text => {
          document.getElementById('msg').innerText = text;
        })
        .catch(err => {
          console.error(err);
          document.getElementById('msg').innerText = "Error calling API";
        });
    });
  </script>
</body>
</html>
