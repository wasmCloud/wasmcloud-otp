function ninentyNineLives() {
  let lifeContainer = document.getElementById("kowasmi-container");
  let life = document.getElementById("kowasmi").cloneNode(true);
  life.style.display = "block";
  life.style.color = "#e55353";
  let numLives = 0;
  let oneLife = () => {
    life = life.cloneNode(true);
    lifeContainer.appendChild(life);
    numLives++;
    if (numLives >= 99) {
      return;
    } else if (numLives % 30 == 0) {
      lifeContainer.appendChild(document.createElement("br"));
    }
    setTimeout(oneLife, 100);
  };
  oneLife();
}

// a key map of allowed keys
var allowedKeys = {
  13: "enter",
  37: "left",
  38: "up",
  39: "right",
  40: "down",
  65: "a",
  66: "b",
};

// the 'official' Kowasmi Code sequence
var kowasmiCode = [
  "up",
  "up",
  "down",
  "down",
  "left",
  "right",
  "left",
  "right",
  "b",
  "a",
  "enter",
];

// a variable to remember the 'position' the user has reached so far.
var kowasmiCodePosition = 0;

// add keydown event listener
document.addEventListener("keydown", function (e) {
  // get the value of the key code from the key map
  var key = allowedKeys[e.keyCode];
  // get the value of the required key from the kowasmi code
  var requiredKey = kowasmiCode[kowasmiCodePosition];

  // compare the key with the required key
  if (key == requiredKey) {
    // move to the next key in the kowasmi code sequence
    kowasmiCodePosition++;

    // if the last key is reached, activate cheats
    if (kowasmiCodePosition == kowasmiCode.length) {
      ninentyNineLives();
      kowasmiCodePosition = 0;
    }
  } else {
    kowasmiCodePosition = key == kowasmiCode[0] ? 1 : 0;
  }
});
