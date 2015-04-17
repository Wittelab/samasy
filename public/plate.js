// Draws the plate image into the target_div_id using the SVG.js library
function draw_plate(target_div_id)
{
		// Get the target div, pass it to SVG.js, add the 'plate' class
	  var plate_name = $("#"+target_div_id).data().id;
		var draw = SVG(target_div_id).attr('class','plate');
		// Create a set of well objects, define the shape of the plate and lettering
		var wells = draw.set();
		draw.viewbox(0,0,127.76,85.48);
		var path = draw.path("M0 0 L0 85.48 L122.76 85.48 L127.76 80.48 L127.76 0 Z");
		var letters = ["A","B","C","D","E","F","G","H"];
		var rowpos = _.range(11.24,75,9);
		var colpos = _.range(14.38,120,9);

		// Add letters/numbers to the plate
		for(i in rowpos) { draw.text(letters[i]).move(7,rowpos[i]); }
		for(i in colpos) { draw.text(String(_.range(1,13)[i])).move(colpos[i],5); }
		for(x in colpos)
		{
			for(y in rowpos)
			{
				var well = draw.circle(7).move(colpos[x]-3.14,rowpos[y]);
				well.attr('row',letters[y]);
				well.attr('col',parseInt(x)+1);
				well.attr('class','loading');
				wells.add(well);
			}
		}
		var load = draw.text('Loading...').attr('class','loading').move("30px","24px").hide();
		draw['name'] = plate_name;
		draw['wells'] = wells;
		draw['load'] = load;
		return draw;
}



function get_well_info(target_div, plate_name, well)
{
	// Get plate info from the server via the JSON route
	// old_well is used to store the original colorings of the previously clicked well
	var old_well = get_well_info.old_well;
	var old_color = get_well_info.old_color;
	var old_class = get_well_info.old_class;
	if (old_well!=undefined)
	{
		old_well.stop();
		// Put the old well stylings back on and the previous color fill
		old_well.attr('class',old_class);
		old_well.style('fill',old_color);
	}
	// Store this wells info for the next click
	get_well_info.old_well  = well;
	get_well_info.old_color = well.style('fill');
	get_well_info.old_class = well.attr('class');

	// Request well info from the server
	$.getJSON('/json/sample/'+plate_name+'/'+well.attr().row+'/'+well.attr().col, function( sample_data )
	{

		// Highlight the well and show the info in the selection panel (color pulse)
		well.style('fill',null)
				.attr('class','selected')
				.style('stroke-width','2.5px')
				.animate(400, '<>',4)
				.style('stroke-width','.5px')


		$('#'+target_div).empty()
		// If no sample is present show fields as unknowns and return
		if(sample_data.length==0)
		{

			$('<h4>')
				.text("This well appears to be empty")
				.appendTo('#'+target_div);
			return;
		}
		// Otherwise fill in the values
		// Plate Type and Study are provided on page load and don't change
		// Sample
		$("#sample-id").text(sample_data.sampleID);
		$('#'+target_div).append('<table>')
		$('<tr>')
		.append($('<td>').text("From"))
		.append($('<td id="mapping-from"style="cursor:pointer;">').text(sample_data.from))
		.appendTo('#'+target_div+' table');
		$('<tr>')
		.append($('<td>').text("To"))
		.append($('<td id="mapping-to" style="cursor:pointer;">').text(sample_data.to))
		.appendTo('#'+target_div+' table');


		$.each(sample_data.attribs,function(attr,value)
		{
			var mod ='<nothing>';
			if (typeof(value) == "string") { value = value.charAt(0).toUpperCase() + value.slice(1); };
			if (typeof(value) == "boolean")
			{
				if(value) {value='  Yes'; mod='<i class="fa fa-check-circle" style="line-height: inherit;">';}
				else {value='  No'; mod='<i class="fa fa-circle-o" style="line-height: inherit;">';}
			}
			$('<tr>')
			.append($('<td>').text(attr))
			.append($('<td>').append($(mod).text(value)))
			.appendTo('#'+target_div+' table');
		});
		// Location
		$("#mapping-from").on("click", function(){ window.location.href="/plate/"+sample_data.from.split(" ")[0];});
		if (sample_data.to!="(Not Mapped)"){ $("#mapping-to").on("click", function(){ window.location.href="/plate/"+sample_data.to.split(" ")[0];}); }
	});
}


var colorscheme;
function generate_color_scheme(attrib, plates)
{
	colorscheme = {};
	var plate_names = [];
	_.each(plates, function (plate){ if (plate.name!==undefined){ plate_names.push(plate.name)} });

	// AJAX load the coloring of each plate
	$.ajax({
		type: 'POST',
		url: '/json/attributes/plates',
		data: {'plates':plate_names, 'attrib':attrib},
		dataType: 'json',
		success: function(values)
		{
			//var colors = ['lightyellow', 'orange', 'deeppink', 'darkred'];
			//colors = chroma.interpolate.bezier(colors);
			//colorscheme = chroma.scale(colors).domain(values).out('hex').mode('lab').correctLightness(true);
			var colors = chroma.brewer.Spectral;
			var undef  = "#eee";
			if (values.length==0) { colorscheme[null] = undef; return; }
			
			colors = chroma.scale(colors).domain(_.range(0,values.length+1)).mode('lab').colors();
			colorscheme = _.object(values,colors)
			colorscheme["N/A"] = undef
			colorscheme[null] = undef
			colorscheme[undefined] = undef
			// For one color, colorscheme defaults to a red value, replace with aquablue
			if (values.length==1){	colorscheme[values[0]] = "#28A8E0"; }
		},
		error: function(error) { console.log("Server error!") },
		async: false
	});
}


// A wrapper to color_wells_by for multiple plates
function color_plates_by(attrib, plates, update_legend)
{
	// Generate a color scheme
	generate_color_scheme(attrib, plates);
	// Color each plate
	_.each(plates, function (plate)
	{
		// Color the wells
		if (plate.name!==undefined)
			{
				if (plates.length>1) { plate.click(function(){window.location = "/plate/"+this.name}); }
				// Color the wells by status (default attribute coloring)
				color_wells_by(attrib, plate);
			}
	});
	draw_legend("well-legend", true, colorscheme, attrib);

	// Prevent selected wells saved old attributes from overwritting new attributes. (old well color bug)
	get_well_info.old_well = undefined;
}

function color_wells_by(attrib, plate)
{
	if(typeof(colorscheme)==='undefined') {generate_color_scheme(attrib, [plate]);}
	plate.load.show();

	$.ajax({
		url: '/json/plate/'+plate.name,
		success: function(plate_data)
		{
			// Set a flag in case we encounter any wells that need to be dashed in the legend
			var show_dashed = false;

			// Get the plate wells to iterate over
			var wells = plate.wells;
			wells.each(function(i)
			{
				var well = wells.members[i];

				var status;
				var color_of = null;
				var well_class = 'unselected';
				// Find information regarding this well
				var well_data = plate_data[well.attr('row')+well.attr('col')];
				if(well_data!=undefined)
				{
						samp_data = well_data['sample'];
						well_data = well_data['well'];
						status = well_data.status;
						if (samp_data!=undefined)
						{
							if(attrib=="status"){ color_of = status } else { color_of = samp_data.attribs[attrib]; }

							if(!well_data.realized)
							{
								well_class = 'unrealized';
								show_dashed = true;
							}
						} else { color_of = null }
				}

				// Color the well using the colorscheme, if null use offwhite
				var color = colorscheme[color_of];
				// Fade from black to this color
				well.style({'fill': "#eee", 'stroke-opacity': .08})
						.animate({duration: 750, ease: '<>', delay: _.random(1,750)})//.animate({duration: _.random(100,800), ease: '>', delay: _.random(1,200)})
						.style({'fill': color, 'stroke-opacity': .6})
						.during(function()
						{
							this.attr('class', well_class);
						});
				// No animation
				//well.style('fill', color).attr('class', well_class);
			});
			$('#'+plate.load.node.id).fadeOut();
		},
		error: function(error) { plate.load.hide(); },
		async: true
	});
}



function draw_legend(target_div_id, show_dashed, colorscheme, title)
{
	// Hide until ready to prevent loading flash
	$('#'+target_div_id).hide();
	if(typeof(show_dashed)==='undefined') show_dashed = false;
	$("#"+target_div_id).empty();

	// Create and capitalize the title
	title = title.charAt(0).toUpperCase() + title.slice(1);
	$("#well-legend-title").html(title);

	// Setup the SVG
	var draw = SVG(target_div_id).size(300, 200);
	y = 10;

	// Draw the legend
	// Draw a gray "Unused well"
	//draw.circle(25).move(10,y).attr("class","plate unselected").fill({'color':'#eeeeee'});
	//draw.text("N/A").move(50,y);

	// For each category in the legend, draw the well
	_.each(_.keys(colorscheme), function(key)
	{
			// Don't display null or undefined in the legend
			if (key=="null" || key=="undefined"){return}
			// Based on the category type, display a bit more intelligently
			var cat_disp = "";
			if (typeof(key) == "string") { cat_disp = key.charAt(0).toUpperCase() + key.slice(1); }
			else if (typeof(key) == "boolean"){ if(key) {cat_disp='Yes';} else {cat_disp='No';} }
			else { cat_disp = key; }

			// Update the row and draw the well and label
			draw.circle(25).move(10,y).attr("class","plate unselected").fill({'color':colorscheme[key]});
			draw.text(String(cat_disp)).move(50,y);
			y = y+30;
	});
	// If any pending wells are used, show this
	if (show_dashed)
	{
			draw.circle(25).move(10,y)
				.style('fill','#fff')
				.attr('stroke','rgba(0, 0, 0, 1)')
				.attr('stroke-width','2px')
				.attr('stroke-dasharray','3.0,2.4');
				// This is prefered, but not rendering correctly
				//.attr('class','unrealized');
			draw.text("Pending").move(50,y);
	}
	draw.attr('height',y+30)
	// Prevents loading flash
	$('#'+target_div_id).fadeIn(100);
}
