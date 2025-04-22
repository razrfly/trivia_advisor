// World Map visualization hook using D3.js and TopoJSON
import * as d3 from "d3";
import * as topojson from "topojson-client";

// Cache the atlas data at the module level
let atlasPromise;
function loadAtlas() {
  if (!atlasPromise) {
    atlasPromise = d3.json("https://cdn.jsdelivr.net/npm/world-atlas@2/countries-110m.json");
  }
  return atlasPromise;
}

const WorldMap = {
  mounted() {
    // Delay setup to ensure DOM is fully rendered
    setTimeout(() => {
      this.setupD3Map();
    }, 100);
  },

  updated() {
    // Clear and redraw the map if data changes
    this.clearMap();
    setTimeout(() => {
      this.setupD3Map();
    }, 100);
  },

  setupD3Map() {
    // Get the map container ID directly from the component's structure
    const componentId = this.el.id;
    const containerId = `world-map-viz-${componentId.replace('world-map-', '')}`;
    
    // Make sure the container element exists
    const containerElement = document.getElementById(containerId);
    if (!containerElement) {
      // Try a fallback approach by finding the container by class inside the component
      const fallbackContainer = this.el.querySelector('.h-\\[400px\\]');
      if (fallbackContainer) {
        return this.renderMapInElement(fallbackContainer);
      }
      return;
    }
    
    this.renderMapInElement(containerElement);
  },
  
  renderMapInElement(containerElement) {
    const container = d3.select(containerElement);
    const containerNode = container.node();
    
    if (!containerNode) {
      console.error("D3 couldn't select the container element");
      return;
    }
    
    const rect = containerNode.getBoundingClientRect();
    const width = rect.width;
    const height = rect.height;
    
    if (width === 0 || height === 0) {
      console.error("Container has zero width or height");
      return;
    }
    
    // Minimum venue count to display a country
    const MIN_VENUES = 1;
    
    // Parse the venue data from the data attribute
    let venuesByCountry;
    try {
      venuesByCountry = JSON.parse(this.el.dataset.venues);
      
      // Filter to only countries with minimum venue count
      venuesByCountry = venuesByCountry.filter(country => country.venue_count >= MIN_VENUES);
      
      if (venuesByCountry.length === 0) {
        // Fallback - reparse all venues
        venuesByCountry = JSON.parse(this.el.dataset.venues);
      }
    } catch (e) {
      console.error("Error parsing venues data:", e);
      return;
    }
    
    // Create an SVG element
    const svg = container.append("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("viewBox", [0, 0, width, height])
      .attr("style", "max-width: 100%; height: auto;");
      
    // Create a group for the map
    const g = svg.append("g");
    
    // Define color scale based on venue count
    const maxVenueCount = d3.max(venuesByCountry, d => d.venue_count) || 100;
    
    // Use a more visible color scale that makes even small values more noticeable
    const colorScale = d3.scalePow()
      .exponent(0.4) // Use a power scale with exponent < 1 to emphasize lower values
      .domain([MIN_VENUES, maxVenueCount])
      .range(["#90c2f6", "#1e40af"]); // Light blue to deep blue
    
    // Set up the projection - using NaturalEarth but with adjustments to show more of Canada
    const projection = d3.geoNaturalEarth1()
      .scale(width / 6)
      .center([-20, 20]) // Shift west and north to better show Canada
      .translate([width / 2, height / 2]);
    
    // Create a path generator
    const path = d3.geoPath().projection(projection);
    
    // Add zoom behavior
    const zoom = d3.zoom()
      .scaleExtent([1, 8])
      .on("zoom", (event) => {
        g.attr("transform", event.transform);
      });
    
    svg.call(zoom);
    
    // Create a map of country codes to venue counts for easy lookup
    const countryData = {};
    
    venuesByCountry.forEach(d => {
      countryData[d.country_code] = {
        name: d.country_name,
        count: d.venue_count
      };
    });
    
    // Load world map data (using TopoJSON)
    loadAtlas()
      .then(world => {
        // Convert TopoJSON to GeoJSON
        const countries = topojson.feature(world, world.objects.countries);
        
        // Create a map of country ids to names for tooltip display
        const countryNames = {};
        const countryIds = {};
        
        world.objects.countries.geometries.forEach(d => {
          countryNames[d.id] = d.properties.name;
          if (!countryIds[d.properties.name]) {
            countryIds[d.properties.name] = [];
          }
          countryIds[d.properties.name].push(d.id);
        });
        
        // Create a direct mapping for specific countries of interest
        const directCountryMapping = {
          "Australia": "AU",
          "United States of America": "US",
          "United States": "US",
          "United Kingdom": "GB",
          "Ireland": "IE",
          "Canada": "CA",
          "New Zealand": "NZ",
          "South Africa": "ZA"
        };
        
        // Create a tooltip
        const tooltip = d3.select("body").append("div")
          .attr("class", "tooltip")
          .style("position", "absolute")
          .style("pointer-events", "none")
          .style("background", "white")
          .style("border", "1px solid #ddd")
          .style("border-radius", "4px")
          .style("padding", "8px")
          .style("font-size", "12px")
          .style("opacity", 0);
        
        // Add a map background in very light blue to represent oceans
        svg.insert("rect", ":first-child")
          .attr("width", width)
          .attr("height", height)
          .attr("fill", "#f0f7ff")
          .attr("rx", 8)
          .attr("ry", 8);
        
        // First, render all countries in a very light color
        g.selectAll(".country-base")
          .data(countries.features)
          .enter()
          .append("path")
          .attr("class", "country-base")
          .attr("d", path)
          .attr("fill", "#e6eef8")  // Very light blue/gray
          .attr("stroke", "#cfd8e3")
          .attr("stroke-width", 0.5);
        
        // Filter out countries that don't have enough venues
        const countriesToShow = countries.features.filter(d => {
          // Get the country name
          const countryName = d.properties.name;
          
          // Try direct name mapping first
          let code = directCountryMapping[countryName];
          
          // If not found, try ID mapping
          if (!code) {
            code = this.getCountryCodeFromId(d.id);
          }
          
          // Special case for Australia
          if (countryName === "Australia" || countryName.includes("Austral")) {
            code = "AU";
          }
          
          // Only keep countries that have enough venue data
          return countryData[code] && countryData[code].count >= MIN_VENUES;
        });
        
        // If no countries match our criteria after filtering, display an error message
        if (countriesToShow.length === 0) {
          container.append("div")
            .style("position", "absolute")
            .style("top", "50%")
            .style("left", "50%")
            .style("transform", "translate(-50%, -50%)")
            .style("padding", "20px")
            .style("background-color", "rgba(255,255,255,0.8)")
            .style("border-radius", "8px")
            .style("text-align", "center")
            .html(`<h3 style="color: #666;">No countries with venues found</h3>`);
          return;
        }
          
        // Draw only the countries with sufficient venues
        g.selectAll(".country-highlight")
          .data(countriesToShow)
          .enter()
          .append("path")
          .attr("class", "country-highlight")
          .attr("d", path)
          .attr("fill", d => {
            // Get the country name
            const countryName = d.properties.name;
            
            // Try direct name mapping first
            let code = directCountryMapping[countryName];
            
            // If not found, try ID mapping
            if (!code) {
              code = this.getCountryCodeFromId(d.id);
            }
            
            // Special case for Australia
            if (countryName === "Australia" || countryName.includes("Austral")) {
              code = "AU";
            }
            
            // At this point we know the country has venue data (from our filter)
            return colorScale(Math.max(MIN_VENUES, countryData[code].count));
          })
          .attr("stroke", "#536480")
          .attr("stroke-width", 1)
          .attr("stroke-linejoin", "round")
          .on("mouseover", function(event, d) {
            // Get the country name
            const countryName = d.properties.name;
            
            // Try direct name mapping first
            let code = directCountryMapping[countryName];
            
            // If not found, try ID mapping
            if (!code) {
              code = WorldMap.getCountryCodeFromId(d.id);
            }
            
            // Special case for Australia
            if (countryName === "Australia" || countryName.includes("Austral")) {
              code = "AU";
            }
            
            // Use the country code to get the venue data
            const data = countryData[code];
            
            // Show tooltip
            tooltip.transition()
              .duration(200)
              .style("opacity", 0.9);
            
            // Set tooltip content
            tooltip.html(`
              <strong>${countryName || "Unknown"}</strong><br/>
              ${data ? `${data.count} venues` : "No venues"}
            `)
              .style("left", (event.pageX + 10) + "px")
              .style("top", (event.pageY - 28) + "px");
            
            // Highlight the country
            d3.select(this)
              .attr("stroke", "#4f46e5")
              .attr("stroke-width", 2);
          })
          .on("mouseout", function() {
            // Hide tooltip
            tooltip.transition()
              .duration(500)
              .style("opacity", 0);
            
            // Reset country styling
            d3.select(this)
              .attr("stroke", "#536480")
              .attr("stroke-width", 1);
          });
      })
      .catch(error => {
        console.error("Error loading world map data:", error);
        container.append("div")
          .style("display", "flex")
          .style("align-items", "center")
          .style("justify-content", "center")
          .style("height", "100%")
          .style("color", "#666")
          .text("Error loading map data");
      });
  },
  
  // Helper method to convert country id to ISO country code
  getCountryCodeFromId(id) {
    // This is an expanded mapping of country ids to ISO codes
    const countryMap = {
      // Oceania
      "36": "AU",   // Australia
      "554": "NZ",  // New Zealand
      
      // North America
      "840": "US",  // United States
      "124": "CA",  // Canada
      "484": "MX",  // Mexico
      
      // Europe
      "826": "GB",  // United Kingdom
      "372": "IE",  // Ireland
      "276": "DE",  // Germany
      "250": "FR",  // France
      "724": "ES",  // Spain
      "380": "IT",  // Italy
      "756": "CH",  // Switzerland
      "56": "BE",   // Belgium
      "056": "BE",  // Belgium (with leading zeros)
      "292": "GI",  // Gibraltar
      "642": "RO",  // Romania
      "620": "PT",  // Portugal
      "246": "FI",  // Finland
      "616": "PL",  // Poland
      "703": "SK",  // Slovakia
      "578": "NO",  // Norway
      "208": "DK",  // Denmark
      "752": "SE",  // Sweden
      "440": "LT",  // Lithuania
      "428": "LV",  // Latvia
      "233": "EE",  // Estonia
      "40": "AT",   // Austria
      "705": "SI",  // Slovenia
      "191": "HR",  // Croatia
      "300": "GR",  // Greece
      "348": "HU",  // Hungary
      "203": "CZ",  // Czech Republic
      
      // Middle East
      "784": "AE",  // United Arab Emirates
      "196": "CY",  // Cyprus
      
      // Asia
      "356": "IN",  // India
      "398": "KZ",  // Kazakhstan
      "156": "CN",  // China
      "704": "VN",  // Vietnam
      "392": "JP",  // Japan
      "410": "KR",  // South Korea
      "458": "MY",  // Malaysia
      "764": "TH",  // Thailand
      "608": "PH",  // Philippines
      "360": "ID",  // Indonesia
      
      // Africa
      "710": "ZA",  // South Africa
      "404": "KE",  // Kenya
      "288": "GH",  // Ghana
      "566": "NG",  // Nigeria
      
      // Special territories
      "833": "IM",  // Isle of Man
      "832": "JE"   // Jersey
    };
    
    // For Australia specifically, let's try different formats
    if (id === '36' || id === 36 || String(id) === "36") {
      return "AU";
    }
    
    // Convert numeric id to string for lookup
    const idStr = String(id);
    return countryMap[idStr] || countryMap[idStr.padStart(3, '0')] || null;
  },
  
  clearMap() {
    // Get the component ID
    const componentId = this.el.id;
    const containerId = `world-map-viz-${componentId.replace('world-map-', '')}`;
    
    // Try to clear by ID
    const containerElement = document.getElementById(containerId);
    if (containerElement) {
      containerElement.innerHTML = "";
    }
    
    // Also try to clear by selector as fallback
    const fallbackContainer = this.el.querySelector('.h-\\[400px\\]');
    if (fallbackContainer) {
      fallbackContainer.innerHTML = "";
    }
    
    // Remove any tooltips
    d3.selectAll(".tooltip").remove();
  }
};

export default WorldMap; 