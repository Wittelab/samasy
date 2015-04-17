var canvas = document.createElement('canvas');
canvas.id = 'c';
// Make it visually fill the positioned parent
canvas.style.width ='100%';
canvas.style.height='100%';
// ...then set the internal size to match
canvas.width  = canvas.offsetWidth;
canvas.height = canvas.offsetHeight;
$("#selection").append(canvas);
$("#selection").css("padding","0px")
var c = document.getElementById("c");
var ctx = c.getContext("2d");

//making the canvas full screen
c.height = $("#selection").height();
c.width = $("#selection").width();

var txt = "ATCG";
//converting the string into an array of single characters
txt = txt.split("");

var font_size = 10;
var columns = c.width/font_size; //number of columns for the rain
//an array of drops - one per column
var drops = [];
//x below is the x coordinate
//1 = y co-ordinate of the drop(same for every drop initially)
for(var x = 0; x < columns; x++)
  drops[x] = 1;

//drawing the characters
function draw()
{
  //Black BG for the canvas
  //translucent BG to show trail
  ctx.fillStyle = "rgba(249,249,249, 0.08);";
  ctx.fillRect(0, 0, c.width, c.height);

  ctx.fillStyle = "#040"; //green text
  ctx.font = font_size + "px arial";
  //looping over drops
  for(var i = 0; i < drops.length; i++)
  {
    //a random txt character to print
    var text = txt[Math.floor(Math.random()*txt.length)];
    //x = i*font_size, y = value of drops[i]*font_size
    ctx.fillText(text, i*font_size, drops[i]*font_size);

    //sending the drop back to the top randomly after it has crossed the screen
    //adding a randomness to the reset to make the drops scattered on the Y axis
    if(drops[i]*font_size > c.height && Math.random() > 0.975)
      drops[i] = 0;

    //incrementing Y coordinate
    drops[i]++;
  }
}

setInterval(draw, 33);
