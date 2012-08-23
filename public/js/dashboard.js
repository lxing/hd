$(function() {
  // Generate a normalized Rickshaw graph in the target id div with data and a descriptor
  graph = function(id, data, name) {
    console.log(data);
    var palette = new Rickshaw.Color.Palette({ scheme: "spectrum14" });
    var series = _.map(data, function(datum) {
      return {
        color: palette.color(),
        data: datum,
        name: name
      };
    })
    Rickshaw.Series.zeroFill(series);
    var graph = new Rickshaw.Graph({
      element: document.querySelector("#" + id),
      renderer: "bar",
      series: series
    });
    var hoverDetail = new Rickshaw.Graph.HoverDetail( { graph: graph } );
    var xAxis = new Rickshaw.Graph.Axis.Time( {
      graph: graph,
      ticksTreatment: "glow"
    });
    var yAxis = new Rickshaw.Graph.Axis.Y( {
      graph: graph,
      tickFormat: Rickshaw.Fixtures.Number.formatKMBT,
      ticksTreatment: "glow"
    });
    graph.render();
  }

});