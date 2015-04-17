// Draws the plate image into the target_div_id using the SVG.js library
function draw_plate(target_div_id)
{
    // Get the target div, pass it to SVG.js, add the 'plate' class
    var plate_name = $("#"+target_div_id).data().id;
    var draw = SVG(target_div_id);
    // Create a set of well objects, define the shape of the plate and lettering
    var wells = draw.set();
    draw.viewbox(0,50,100,100);
    //var path = draw.path("M0 0 L0 85.48 L122.76 85.48 L127.76 80.48 L127.76 0 Z");
    var letters = ["A","B","C","D","E","F","G","H"];
    var rowpos = _.range(5,300,10);
    var colpos = _.range(5,100,10);

    // Add letters/numbers to the plate
    //for(i in rowpos) { draw.text(letters[i]).move(7,rowpos[i]); }
    //for(i in colpos) { draw.text(String(_.range(1,13)[i])).move(colpos[i],5); }
    for(x in colpos)
    {
      for(y in rowpos)
      {
        var well = draw.circle(7).move(colpos[x]-3.14,rowpos[y]);
        well.attr('row',letters[y]);
        well.attr('col',parseInt(x)+1);
        //well.fill("#fff");
        well.opacity("0");
        wells.add(well);
      }
    }
    var load = draw.text('Loading...').attr('class','loading').move("30px","24px").hide();
    draw['name'] = plate_name;
    draw['wells'] = wells;
    draw['load'] = load;
    return draw;
}

drawing = draw_plate("selection");
var color_scheme = d3.scale.category20()

setInterval(function(){

  well = drawing.wells.members[_.random(1,drawing.wells.members.length)];
  well.fill(color_scheme(_.random(1,20)));
  well.opacity(".7");
  setTimeout(function(well){
    well.opacity("0");

  }, 1000, well);
}, 200);
