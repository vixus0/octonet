d3.json("result.json").then(function chart(data) {
  function size(d) {
    return 5 + Math.log(d.size*2 + 1);
  }

  function radial(d) {
    const radii = {
      "team": 200,
      "user": 400,
      "repo": 0
    }
    return radii[d.type];
  }

  function fill(d) {
    const colors = {
      "team": "#d08770",
      "user": "#b48ead",
      "repo": "#a3be8c"
    }
    return colors[d.type]; 
  }

  const width = 2000;
  const height = 1500;

  const links = data.links.map(d => Object.create(d));
  const teams = data.teams.map(d => Object.create(d));
  const members = data.members.map(d => Object.create(d));
  const repos = data.repos.map(d => Object.create(d));
  const nodes = teams.concat(members, repos);

  const simulation = d3.forceSimulation(nodes)
      .force("link", d3.forceLink(links).id(d => d.id))
      .force("collide", d3.forceCollide(d => size(d)))
      .force("charge", d3.forceManyBody(-30))
      .force("center", d3.forceCenter(width / 2, height / 2))
      .force("radial", d3.forceRadial(d => radial(d), width/2, height/2))
      .stop();

  const svg_top = d3.select("svg#graph")
      .attr("viewBox", [0, 0, width, height]);

  const svg = svg_top.append("g");

  svg_top.call(d3.zoom().on("zoom", function () {
         svg.attr("transform", d3.event.transform);
      }));

  for (var i=0; i < 100; i++) simulation.tick();

  d3.select("text#loading").remove();

  const link = svg.append("g")
      .attr("stroke", "#999")
      .attr("stroke-opacity", 0.6)
      .selectAll("line")
      .data(links)
      .join("line")
      .attr("source-id", d => d.source.id)
      .attr("target-id", d => d.target.id)
      .attr("stroke-width", 1)
      .attr("x1", d => d.source.x)
      .attr("y1", d => d.source.y)
      .attr("x2", d => d.target.x)
      .attr("y2", d => d.target.y);

  /*
  // Avatars
  const defs = svg.append('defs')
      .selectAll("pattern")
      .data(members)
      .enter()
      .append("pattern")
      .attr("id", d => d.id)
      .attr("width", d => size(d))
      .attr("height", d => size(d))
      .attr("patternUnits", "userSpaceOnUse")
      .append("image")
      .attr("xlink:href", d => d.avatar)
      .attr("width", "100%")
      .attr("height", "100%")
      .attr("preserveAspectRatio", "xMinYMin")
      .attr("x", 0)
      .attr("y", 0);
      */

  const node = svg.append("g")
      .attr("stroke", "#fff")
      .attr("stroke-width", 1.5)
      .selectAll("circle")
      .data(nodes)
      .join("circle")
      .attr("id", d => d.id)
      .attr("r", d => size(d))
      .attr("fill", d => fill(d))
      .attr("cx", d => d.x)
      .attr("cy", d => d.y)
      .on("mouseover", handleMouseOver)
      .on("mouseout", handleMouseOut)
      .on("click", handleClick);

  node.append("title")
      .text(d => d.id);

  /*
  simulation.on("tick", () => {
    link
        .attr("x1", d => d.source.x)
        .attr("y1", d => d.source.y)
        .attr("x2", d => d.target.x)
        .attr("y2", d => d.target.y);

    node
        .attr("cx", d => d.x)
        .attr("cy", d => d.y);
  });
  */

  function highlight(d, node, toggle_attr) {
    if (node.attr("select") !== "clicked") {
      d3.selectAll(`line[source-id="${d.id}"], line[target-id="${d.id}"]`).each(function(d, i) {
        const link = d3.select(this);
        link.attr("select", toggle_attr)
            .attr("stroke-width", 3);
        d3.selectAll(`circle#${link.attr("source-id")}, circle#${link.attr("target-id")}`)
          .attr("select", toggle_attr)
          .attr("stroke", "#808080");
      });
      node.attr("select", toggle_attr)
          .attr("stroke", "#101010");
    }
  }

  function unhighlightAll(toggle_attr) {
    d3.selectAll(`line[select="${toggle_attr}"]`)
      .attr("stroke-width", 1);
    d3.selectAll(`circle[select="${toggle_attr}"]`)
      .attr("select", null)
      .attr("stroke", "#fff");
  }

  function unhighlight(node, toggle_attr) {
    if (node.attr("select") === toggle_attr) {
      unhighlightAll(toggle_attr);
      node.attr("select", null)
          .attr("stroke", "#fff");
    }
  }

  function handleMouseOver(d, i) {
    highlight(d, d3.select(this), "hover");
  }

  function handleMouseOut(d, i) {
    unhighlight(d3.select(this), "hover");
  }

  function handleClick(d, i) {
    const node = d3.select(this);
    unhighlightAll("clicked");
    highlight(d, node, "clicked");
  }

  // Search
  const search = document.getElementById("search");
  search.addEventListener("change", searchChange);

  function searchChange(e) {
    const text = e.srcElement.value.trim();
    const results = d3.select("#search-results");
    results.selectAll("li").remove();
    d3.selectAll("circle").attr("fill", d => fill(d));

    if (text !== "") {
      const items = d3.selectAll("circle").filter(d => `${d.id} ${d.name}`.includes(text));
      if (items.size() > 0) {
        d3.selectAll("circle").attr("fill", "#d8dee9");
        items.attr("fill", d => fill(d));
        results.selectAll("li")
               .data(items.data())
               .enter()
               .append("li")
               .attr("data-type", d => d.type)
               .text(d => d.label);
      }
    }
  }

  return svg.node();
})