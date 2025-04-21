// World Map visualization hook using D3.js and TopoJSON
import * as d3 from "d3";
import * as topojson from "topojson-client";

const WorldMap = {
  mounted() {
    console.log("WorldMap hook mounted, element ID:", this.el.id);
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
    console.log("Setting up D3 map...");
    
    // Get the map container ID directly from the component's structure
    // The map viz container is a child element with ID that follows a specific pattern
    const componentId = this.el.id;
    const containerId = `world-map-viz-${componentId.replace('world-map-', '')}`;
    
    console.log("Component ID:", componentId);
    console.log("Target container ID:", containerId);
    
    // Make sure the container element exists
    const containerElement = document.getElementById(containerId);
    if (!containerElement) {
      console.error(`Element with ID "${containerId}" not found in the DOM`);
      // Let's try a fallback approach by finding the container by class inside the component
      const fallbackContainer = this.el.querySelector('.h-\\[400px\\]');
      if (fallbackContainer) {
        console.log("Found container using fallback selector");
        // Use the container we found directly instead of by ID
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
    
    console.log("Container dimensions:", width, height);
    
    if (width === 0 || height === 0) {
      console.error("Container has zero width or height");
      return;
    }
    
    // Parse the venue data from the data attribute
    let venuesByCountry;
    try {
      venuesByCountry = JSON.parse(this.el.dataset.venues);
      console.log("Parsed venues data:", venuesByCountry.length, "countries");
      
      // Debug: Log all countries and their codes for verification
      venuesByCountry.forEach(country => {
        console.log(`Country: ${country.country_name}, Code: ${country.country_code}, Venues: ${country.venue_count}`);
      });
      
      // Specifically look for Australia in the data
      const australiaData = venuesByCountry.find(c => c.country_name === "Australia" || c.country_code === "AU");
      if (australiaData) {
        console.log("FOUND AUSTRALIA IN DATA:", australiaData);
      } else {
        console.error("AUSTRALIA NOT FOUND IN DATA!");
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
    console.log("Max venue count:", maxVenueCount);
    
    // Use a more visible color scale that makes even small values more noticeable
    // We'll use a non-linear scale with a smaller exponent to emphasize lower values
    // This will make countries with fewer venues more visible
    const colorScale = d3.scalePow()
      .exponent(0.4) // Use a power scale with exponent < 1 to emphasize lower values
      .domain([0, maxVenueCount])
      .range(["#f1f5f9", "#1e40af"]); // Light gray to deep blue
    
    // Set up the projection
    const projection = d3.geoNaturalEarth1()
      .scale(width / 5.5)
      .translate([width / 2, height / 1.8]);
    
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
    d3.json("https://cdn.jsdelivr.net/npm/world-atlas@2/countries-110m.json")
      .then(world => {
        console.log("World map data loaded successfully");
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
        
        // Debug: Log all country IDs and names
        console.log("All country IDs from map data:");
        Object.entries(countryNames).forEach(([id, name]) => {
          console.log(`ID: ${id}, Name: ${name}`);
        });
        
        // Debug: Check specifically for Australia
        const australiaIds = countryIds["Australia"] || [];
        if (australiaIds.length > 0) {
          console.log("Australia IDs in map data:", australiaIds);
        } else {
          console.error("Australia not found in map data!");
          
          // Try to find Australia by approximate name match
          const possibleMatches = Object.entries(countryNames)
            .filter(([_, name]) => name.includes("Austral") || name === "Oceania")
            .map(([id, name]) => ({id, name}));
          
          console.log("Possible Australia matches:", possibleMatches);
        }
        
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
        
        // Draw the countries
        g.selectAll("path")
          .data(countries.features)
          .enter()
          .append("path")
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
            
            // Debug info for Australia
            if (countryName === "Australia" || countryName.includes("Austral")) {
              console.log("Australia path check:", {
                id: d.id, 
                name: countryName, 
                directCode: directCountryMapping[countryName],
                idMappedCode: this.getCountryCodeFromId(d.id),
                finalCode: code,
                hasVenueData: !!countryData[code],
                venueCount: countryData[code]?.count
              });
            }
            
            // Special case for Australia
            if (countryName === "Australia" || countryName.includes("Austral")) {
              // Force Australia to use AU code
              return countryData["AU"] ? colorScale(Math.max(1, countryData["AU"].count)) : "#f1f5f9";
            }
            
            // Use the country code to get the venue count
            // Make any country with at least 1 venue have some color
            return countryData[code] ? colorScale(Math.max(1, countryData[code].count)) : "#f1f5f9";
          })
          .attr("stroke", "#cfd8e3")
          .attr("stroke-width", 0.5)
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
              .attr("stroke-width", 1.5);
          })
          .on("mouseout", function() {
            // Hide tooltip
            tooltip.transition()
              .duration(500)
              .style("opacity", 0);
            
            // Reset country styling
            d3.select(this)
              .attr("stroke", "#cfd8e3")
              .attr("stroke-width", 0.5);
          });
          
        // Add a legend
        const legendWidth = 180;
        const legendHeight = 15;
        const legend = svg.append("g")
          .attr("transform", `translate(${width - legendWidth - 20}, ${height - 40})`);
          
        // Create a gradient for the legend
        const defs = svg.append("defs");
        const gradientId = `legend-gradient-${Date.now()}`; // Use timestamp for uniqueness
        const linearGradient = defs.append("linearGradient")
          .attr("id", gradientId)
          .attr("x1", "0%")
          .attr("y1", "0%")
          .attr("x2", "100%")
          .attr("y2", "0%");
          
        // Add color stops to the gradient
        linearGradient.append("stop")
          .attr("offset", "0%")
          .attr("stop-color", colorScale(0));
          
        linearGradient.append("stop")
          .attr("offset", "20%")
          .attr("stop-color", colorScale(1)); // Show what even 1 venue looks like
          
        linearGradient.append("stop")
          .attr("offset", "50%")
          .attr("stop-color", colorScale(Math.ceil(maxVenueCount * 0.25)));
          
        linearGradient.append("stop")
          .attr("offset", "100%")
          .attr("stop-color", colorScale(maxVenueCount));
          
        // Add the colored rectangle
        legend.append("rect")
          .attr("width", legendWidth)
          .attr("height", legendHeight)
          .style("fill", `url(#${gradientId})`) // Use unique gradient ID
          .style("stroke", "#ccc")
          .style("stroke-width", 0.5);
          
        // Add the legend title
        legend.append("text")
          .attr("x", 0)
          .attr("y", -5)
          .style("font-size", "10px")
          .style("fill", "#666")
          .text("Venue Count");
          
        // Add legend labels
        legend.append("text")
          .attr("x", 0)
          .attr("y", legendHeight + 12)
          .style("font-size", "10px")
          .style("fill", "#666")
          .text("0");
          
        legend.append("text")
          .attr("x", legendWidth * 0.2)
          .attr("y", legendHeight + 12)
          .style("font-size", "10px")
          .style("fill", "#666")
          .text("1+");
          
        legend.append("text")
          .attr("x", legendWidth * 0.5)
          .attr("y", legendHeight + 12)
          .style("font-size", "10px")
          .style("fill", "#666")
          .text(`${Math.ceil(maxVenueCount * 0.25)}+`);
          
        legend.append("text")
          .attr("x", legendWidth)
          .attr("y", legendHeight + 12)
          .style("font-size", "10px")
          .style("text-anchor", "end")
          .style("fill", "#666")
          .text(`${maxVenueCount}+`);
          
        console.log("Map visualization complete");
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
    // We need to make sure we have the correct numeric IDs from the TopoJSON data
    const countryMap = {
      // Oceania
      36: "AU",   // Australia
      554: "NZ",  // New Zealand
      
      // North America
      840: "US",  // United States
      124: "CA",  // Canada
      484: "MX",  // Mexico
      
      // Europe
      826: "GB",  // United Kingdom
      372: "IE",  // Ireland
      276: "DE",  // Germany
      250: "FR",  // France
      724: "ES",  // Spain
      380: "IT",  // Italy
      756: "CH",  // Switzerland
      56: "BE",   // Belgium
      56: "BE",   // Belgium (as string)
      "056": "BE",  // Belgium (as string with leading zeros)
      292: "GI",  // Gibraltar
      642: "RO",  // Romania
      620: "PT",  // Portugal
      246: "FI",  // Finland
      616: "PL",  // Poland
      703: "SK",  // Slovakia
      578: "NO",  // Norway
      208: "DK",  // Denmark
      752: "SE",  // Sweden
      440: "LT",  // Lithuania
      428: "LV",  // Latvia
      233: "EE",  // Estonia
      40:  "AT",  // Austria
      705: "SI",  // Slovenia
      191: "HR",  // Croatia
      300: "GR",  // Greece
      348: "HU",  // Hungary
      203: "CZ",  // Czech Republic
      
      // Middle East
      784: "AE",  // United Arab Emirates
      196: "CY",  // Cyprus
      
      // Asia
      356: "IN",  // India
      398: "KZ",  // Kazakhstan
      156: "CN",  // China
      704: "VN",  // Vietnam
      392: "JP",  // Japan
      410: "KR",  // South Korea
      458: "MY",  // Malaysia
      764: "TH",  // Thailand
      608: "PH",  // Philippines
      360: "ID",  // Indonesia
      
      // Africa
      710: "ZA",  // South Africa
      404: "KE",  // Kenya
      288: "GH",  // Ghana
      566: "NG",  // Nigeria
      
      // Special territories
      833: "IM",  // Isle of Man
      832: "JE"   // Jersey
    };
    
    // Log every ID lookup for debugging
    console.log(`Looking up country code for ID: ${id}, Result: ${countryMap[id]}`);
    
    // For Australia specifically, let's try different formats
    if (id === '36' || id === 36 || String(id) === "36") {
      console.log("Australia ID direct match found!");
      return "AU";
    }
    
    return countryMap[id] || null;
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