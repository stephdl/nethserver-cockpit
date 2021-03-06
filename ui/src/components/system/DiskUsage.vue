<template>
  <div v-if="view.isAuth">
    <h2>{{$t('disk_usage.title')}}</h2>
    <h3>{{$t('actions')}}</h3>
    <button @click="updateJSONUsage()" class="btn btn-primary btn-lg" type="button">{{$t('disk_usage.update_data')}}</button>
    <h4>{{$t('disk_usage.update_at')}} <b>{{disk.updatedAt | dateFormat}}</b></h4>

    <div v-if="!view.isLoaded" class="spinner"></div>

    <h3>{{$t('info')}}</h3>
    <div id="baseContainer" v-if="view.isLoaded">
      <a href="" onclick="$.reset();" id="baseBread">/</a>
    </div>
    <div id="sequence" v-if="view.isLoaded"></div>

    <div id="explanation" v-if="view.isLoaded">
      <button @click="copyPath()" class="btn btn-primary copy-path" type="button">{{$t('disk_usage.copy_path')}}</button>
      <span v-if="view.copied" class="fa fa-check green copy-ok"></span>
      <p id="sizeFolder"></p>
    </div>

    <div id="chart" v-if="view.isLoaded">
    </div>
  </div>
</template>

<script>
export default {
  name: "DiskUsage",
  beforeRouteEnter(to, from, next) {
    next(vm => {
      vm.exec(
        ["system-authorization/read"],
        null,
        null,
        function(success) {
          success = JSON.parse(success);

          if (success.system.indexOf(to.path.substring(1)) == -1) {
            window.location.hash = "#/";
            vm.$router.push("/");
          }

          vm.view.isAuth = true;
        },
        function(error) {
          console.error(error);
        },
        false
      );
    });
  },
  mounted() {
    this.getJSONUsage();
    this.drawChart();
  },
  data() {
    return {
      disk: {
        updatedAt: 0
      },
      view: {
        isLoaded: true,
        isAuth: false,
        copied: false
      }
    };
  },
  methods: {
    copyPath() {
      var context = this;
      context.$copyText($("#baseBread").html()).then(
        function(e) {
          context.view.copied = true;
          setTimeout(function() {
            context.view.copied = false;
          }, 2000);
        },
        function(e) {
          context.view.copied = false;
        }
      );
    },
    drawChart() {
      var context = this;

      // disk draw methods (using d3.js)
      (function($) {
        $.duc = function() {
          // Dimensions of sunburst.
          var width = window.innerWidth;
          var height = window.innerHeight;
          var radius = Math.min(height, width) / 3;

          // Breadcrumb dimensions: width, height, spacing, width of tip/tail.
          var b = {
            w: window.innerWidth * 80 / 1920,
            h: 20,
            s: 3,
            t: 10
          };

          var total = 0;
          var breadCumbText = window.innerWidth * 6 / 1920;

          var baseDir = "/";
          var arcDefault;

          // Keep track of the node that is currently being displayed as the root.
          var node;
          var path;

          // Total size of all segments; we set this later, after loading the data.
          var totalSize = 0;

          var x = d3.scaleLinear().range([0, 2 * Math.PI]);
          var y = d3.scaleSqrt().range([0, radius]);
          var color = d3.scaleOrdinal(d3.schemeCategory10);

          var svg = d3
            .select("#chart")
            .append("svg:svg")
            .attr("width", width)
            .attr("height", height)
            .append("svg:g")
            .attr("id", "container")
            .attr(
              "transform",
              "translate(" + width / 2 + "," + height / 2.3 + ")"
            );

          var partition = d3.partition();

          var arc = d3
            .arc()
            .startAngle(function(d) {
              return Math.max(0, Math.min(2 * Math.PI, x(d.x0)));
            })
            .endAngle(function(d) {
              return Math.max(0, Math.min(2 * Math.PI, x(d.x1)));
            })
            .innerRadius(function(d) {
              return Math.max(0, y(d.y0));
            })
            .outerRadius(function(d) {
              return Math.max(0, y(d.y1));
            });

          function createVisualization(json) {
            json.name = "root";
            var root = d3
              .hierarchy(json)
              .sum(function(d) {
                return d.size_actual;
              })
              .sort(function(a, b) {
                return b.size_actual - a.size_actual;
              });

            arcDefault = root;
            node = root;

            var nodes = partition(root)
              .descendants()
              .filter(function(d) {
                return true; // 0.005 radians = 0.29 degrees
              });

            path = svg
              .data([json])
              .selectAll("path")
              .data(nodes)
              .enter()
              .append("svg:path")
              .attr("d", arc)
              .attr("fill-rule", "evenodd")
              .style("fill", function(d) {
                return color(d.data.name);
              })
              .style("opacity", 1)
              .on("click", click)
              .on("dblclick", gotoBase)
              .on("mouseover", mouseover)
              .each(stash);

            // Add the mouseleave handler to the bounding circle.
            d3.select("#container").on("mouseleave", mouseleave);

            d3.selectAll("input").on("change", function change() {
              var value =
                this.value === "count"
                  ? function() {
                      return 1;
                    }
                  : function(d) {
                      return d.size_actual;
                    };

              path
                .data(partition.value(value).nodes)
                .transition()
                .duration(250)
                .attrTween("d", arcTweenData);
            });

            var sizeFolder = document.getElementById("sizeFolder");
            sizeFolder.innerHTML = context.$options.filters.byteFormat(
              root.size_actual
            );

            function click(d) {
              node = d;
              path
                .transition()
                .duration(250)
                .attrTween("d", arcTweenZoom(d));
            }

            function gotoBase() {
              path
                .transition()
                .duration(250)
                .attrTween("d", arcTweenZoom(arcDefault));
            }
          }

          d3.select(self.frameElement).style("height", height + "px");

          $.reset = function() {
            path
              .transition()
              .duration(250)
              .attrTween("d", arcTweenZoom(arcDefault));
          };

          function mouseleave(d) {
            d3.selection.prototype.first = function() {
              return d3.select(this[0][0]);
            };

            // Deactivate all segments during transition.
            d3.selectAll("path").on("mouseover", null);

            // Transition each segment to full opacity and then reactivate it.
            d3
              .selectAll("path")
              .transition()
              .duration(10)
              .style("opacity", 1)
              .on("end", function() {
                d3.select(this).on("mouseover", mouseover);
              });

            d3
              .select("#sizeFolder")
              .text(context.$options.filters.byteFormat(d.size_actual));
          }

          function mouseover(d) {
            d3
              .select("#sizeFolder")
              .text(context.$options.filters.byteFormat(d.data.size_actual));

            d3.select("#explanation").style("visibility", "");

            var sequenceArray = d.ancestors().reverse();
            sequenceArray.shift();
            updateBreadcrumbs(sequenceArray);

            // Fade all the segments.
            d3.selectAll("path").style("opacity", 0.3);

            // Then highlight only those that are an ancestor of the current segment.
            svg
              .selectAll("path")
              .filter(function(node) {
                if (node.root) return node;
                return sequenceArray.indexOf(node) >= 0;
              })
              .style("opacity", 1);
          }

          // Generate a string that describes the points of a breadcrumb polygon.
          function breadcrumbPoints(d, i) {
            var points = [];
            points.push("0,0");
            points.push(b.w + ",0");
            points.push(b.w + b.t + "," + b.h / 2);
            points.push(b.w + "," + b.h);
            points.push("0," + b.h);
            if (i > 0) {
              // Leftmost breadcrumb; don't include 6th vertex.
              points.push(b.t + "," + b.h / 2);
            }
            return points.join(" ");
          }

          function updateBreadcrumbs(nodeArray) {
            var dirs = nodeArray.map(function(i) {
              return i.data.name;
            });

            $("#baseBread").text("/" + dirs.join("/"));
          }

          function truncate(n, len) {
            if (n) {
              var ext = n.substring(n.length, n.length).toLowerCase();
              var filename = n.replace(ext, "");
              if (filename.length < len) {
                return n;
              }
              filename =
                filename.substr(0, len) + (n.length > len ? "..." : "");
              return filename + ext;
            }
          }

          // Setup for switching data: stash the old values for transition.
          function stash(d) {
            d.xx0 = d.x0;
            d.xx1 = d.x1;
          }

          // When switching data: interpolate the arcs in data space.
          function arcTweenData(a, i) {
            var oi = d3.interpolate(
              { x0: a.x0s ? a.x0s : 0, x1: a.x1s ? a.x1s : 0 },
              a
            );
            function tween(t) {
              var b = oi(t);
              a.x0s = b.x0;
              a.x1s = b.x1;
              return arc(b);
            }
            if (i == 0) {
              var xd = d3.interpolate(x.domain(), [node.x0, node.x1]);
              return function(t) {
                x.domain(xd(t));
                return tween(t);
              };
            } else {
              return tween;
            }
          }

          // When zooming: interpolate the scales.
          function arcTweenZoom(d) {
            var xd = d3.interpolate(x.domain(), [d.x0, d.x1]),
              yd = d3.interpolate(y.domain(), [d.y0, 1]),
              yr = d3.interpolate(y.range(), [d.y0 ? 20 : 0, radius]);
            return function(d, i) {
              return i
                ? function(t) {
                    return arc(d);
                  }
                : function(t) {
                    x.domain(xd(t));
                    y.domain(yd(t)).range(yr(t));
                    return arc(d);
                  };
            };
          }

          return createVisualization;
        };
      })(jQuery);
    },

    getJSONUsage() {
      var context = this;

      context.exec(
        ["system-disk-usage/read"],
        null,
        null,
        function(success) {
          success = JSON.parse(success);
          context.view.isLoaded = true;

          var cv = $.duc();
          cv(success.status.data.duc);

          context.disk.updatedAt = success.status.date;
        },
        function(error) {
          console.error(error);
          context.view.isLoaded = true;
        }
      );
    },
    updateJSONUsage() {
      var context = this;

      context.exec(
        ["system-disk-usage/update"],
        null,
        function(stream) {
          console.info("disk-usage", stream);
        },
        function(success) {
          // notification
          context.$parent.notifications.success.message = context.$i18n.t(
            "disk_usage.disk_updated_ok"
          );

          // get hosts
          window.location.reload();
        },
        function(error, data) {
          // notification
          context.$parent.notifications.error.message = context.$i18n.t(
            "disk_usage.disk_updated_error"
          );
        }
      );
    }
  }
};
</script>

<style>
</style>