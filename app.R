# ---------------- Importing Libraries ----------------------
library(shiny)
library(tidyverse)
library(ggplot2)
library(scales)
library(rnaturalearth)
library(rnaturalearthdata)
library(sf)
library(bslib)
library(gt)
library(WDI)
library(scales)
library(ggrepel)
library(ggtext)

# -------------------- Data loading --------------------

# Loading data for first page - map and time series plots
covid <- read.csv("data/worldometer_coronavirus_daily_data.csv")
world <- ne_countries(scale = "medium", returnclass = "sf")

# Loading data for second page - WDI economic indicators 
economics_data <- WDI(
  country = "all",         # all countries across the world
  indicator = c(
    "NY.GDP.PCAP.KD",      # GDP per capita
    "SH.MED.PHYS.ZS"       # Physicians per 1000 people 
  ),
  start = 2019,  end = 2019, # only one year, 2019, just before the outbreak (which was in early 2020)
  extra = TRUE
)

# -------------------- Data cleaning --------------------

# Dealing with negative numbers of cases and deaths 
covid <- covid %>% 
  mutate(
    date = as.Date(date, format = "%Y-%m-%d"),  # putting the date column into Date format
    daily_new_cases = ifelse(daily_new_cases < 0, 0, daily_new_cases),
    active_cases = ifelse(active_cases < 0, 0, active_cases),
    daily_new_deaths = ifelse(daily_new_deaths < 0, 0, daily_new_deaths)
  ) %>% 
  filter(date >= as.Date("2020-02-15")) # Starting the data from ~1 month before shutdown in mid-March

# Filtering out Antarctica (irrelevant)
world <- world %>% filter(admin != "Antarctica")

# List of name corrections for correct merging
name_corrections <- c(
  "Antigua And Barbuda" = "Antigua and Barb.",
  "Bosnia And Herzegovina" = "Bosnia and Herz.",
  "British Virgin Islands" = "British Virgin Is.",
  "Brunei Darussalam" = "Brunei",
  "Cabo Verde" = "Cabo Verde",
  "Caribbean Netherlands" = "Netherlands",
  "Cayman Islands" = "Cayman Is.", 
  "Central African Republic" = "Central African Rep.",
  "Cook Islands" = "Cook Is.",
  "Channel Islands" = "Jersey", 
  "China Hong Kong Sar" = "Hong Kong",
  "China Macao Sar" = "Macao",
  "Cote D Ivoire" = "Côte d'Ivoire",
  "Curacao" = "Curaçao",
  "Czech Republic" = "Czechia",
  "Democratic Republic Of The Congo" = "Dem. Rep. Congo",
  "Dominican Republic" = "Dominican Rep.",
  "Equatorial Guinea" = "Eq. Guinea",
  "Faeroe Islands" = "Faeroe Is.",
  "Falkland Islands Malvinas" = "Falkland Is.",
  "French Polynesia" = "Fr. Polynesia",
  "French Guiana" = "France",
  "Gibraltar" = "United Kingdom",
  "Guadeloupe" = "France", 
  "Guinea Bissau" = "Guinea-Bissau",
  "Holy See" = "Vatican",
  "Isle Of Man" = "Isle of Man",
  "Macedonia" = "North Macedonia",
  "Marshall Islands" = "Marshall Is.", 
  "Martinique" = "France", 
  "Mayotte" = "France", 
  "Reunion" = "France",
  "Saint Barthelemy" = "St-Barthélemy",
  "Saint Kitts And Nevis" = "St. Kitts and Nevis",
  "Saint Lucia" = "Saint Lucia",
  "Saint Martin" = "St-Martin",
  "Saint Pierre And Miquelon" = "St. Pierre and Miquelon",
  "Saint Vincent And The Grenadines" = "St. Vin. and Gren.",
  "Sao Tome And Principe" = "São Tomé and Principe",
  "Solomon Islands" = "Solomon Is.", 
  "South Sudan" = "S. Sudan", 
  "State Of Palestine" = "Palestine", 
  "Swaziland" = "eSwatini",
  "The Gambia" = "Gambia",
  "Timor Leste" = "Timor-Leste",
  "Trinidad And Tobago" = "Trinidad and Tobago",
  "Turks And Caicos Islands" = "Turks and Caicos Is.",
  "UK" = "United Kingdom",
  "USA" = "United States of America",
  "Viet Nam" = "Vietnam",
  "Wallis And Futuna Islands" = "Wallis and Futuna Is.", 
  "Western Sahara" = "W. Sahara"
)

# Recoding the names in the covid dataset to match with the world dataset
covid$country <- recode(covid$country, !!!name_corrections)

# Merging the world and covid datasets together for the map plot 
covid_filtered <- covid %>%
  select(date, country, 
         cumulative_total_cases, daily_new_cases, 
         active_cases, cumulative_total_deaths, daily_new_deaths
  )
world_covid_data <- inner_join(world, covid_filtered, by = c("name" = "country")) 

# Some variable labels for the first page's plots
var_labels <- c(
  "Cumulative total cases" = "cumulative_total_cases",
  "Daily new cases" = "daily_new_cases",
  "Active cases" = "active_cases",
  "Cumulative total deaths" = "cumulative_total_deaths",
  "Daily new deaths" = "daily_new_deaths"
)

# Computing the per 1M variables for the world map
world_covid_data <- world_covid_data %>% 
  mutate(
    cumulative_total_cases_per_1M = ((cumulative_total_cases / pop_est) * 1e6) + 1e-6, # adding a small number for numerical stability
    daily_new_cases_per_1M = ((daily_new_cases / pop_est) * 1e6) + 1e-6,
    active_cases_per_1M = ((active_cases / pop_est) * 1e6) + 1e-6,
    cumulative_total_deaths_per_1M = ((cumulative_total_deaths / pop_est) * 1e6) + 1e-6,
    daily_new_deaths_per_1M = ((daily_new_deaths / pop_est) * 1e6) + 1e-6
  )

# Cleaning the economic indicators data & merging with the COVID data for plotting 
econ_clean <- economics_data %>%
  select( # selecting the relevant columns
    country = country,
    gdp_per_cap = NY.GDP.PCAP.KD, 
    physicians = SH.MED.PHYS.ZS
  )
econ_covid_merged <- world_covid_data %>% 
  st_drop_geometry() %>%                                                # dropping the geometry (not plotting on a map here)
  filter(date == "2022-05-14") %>%                                      # selecting a specific date 
  select(name,date,region_un,cumulative_total_deaths_per_1M) %>%        # selecting relevant columns for merging
  drop_na() %>%                                                         # Dropping rows with NAs
  mutate(country = name) %>%                                            # creating a row name to match the econ_clean dataset
  distinct(country, .keep_all = TRUE) %>%                               # removing any duplicates in the country column
  left_join(econ_clean, by = "country") %>%                             # inner join with the econ dataset
  select(country, region_un, cumulative_total_deaths_per_1M,            # select only relevant columns after the join 
         gdp_per_cap, physicians) %>% 
  drop_na()                                                             # dropping NAs again after merging

# Creating datasets of outliers to label them in the second page's scatter plots
outliers_gdp <- econ_covid_merged %>% 
  filter((gdp_per_cap > 10000 & cumulative_total_deaths_per_1M < 50) | gdp_per_cap > 100000)
outliers_physicians <- econ_covid_merged %>% 
  filter((physicians > 1 & cumulative_total_deaths_per_1M < 30))

# -------------------- App UI --------------------

ui <- page_navbar(
  
  # Setting the theme
  theme = bslib::bs_theme(bootswatch = "sandstone"),
  
  # Dashboard title
  title = "COVID-19 Impact Dashboard",
  
  # PAGE 1: Spatial-Temporal COVID Growth
  nav_panel(
    title = "Geographic/Temporal COVID Growth",
    
    layout_sidebar(
      sidebar = sidebar(
        # User-input 1: select which variable is being displayed
        selectInput(
          "var", 
          "Select Variable:", 
          choices = var_labels, 
          selected = "active_cases"
        ),
        
        # User-input 2: select which date to display for the maps data. 
        sliderInput("date",
                    "Select Date (30 day intervals):",
                    min = min(world_covid_data$date, na.rm = TRUE),
                    max = max(world_covid_data$date, na.rm = TRUE),
                    value = as.Date("2020-02-15"),
                    step = 30,   # timestep for the slider
                    timeFormat = "%Y-%m-%d",
                    animate = TRUE    # add the 'play' button for easy viewing of continuous change
        ),
        p('Press the above "play" button to see continuous change over time.'),
      ),
      
      # Helper text for page 1
      p("This page helps explain the spatial and temporal growth of COVID-19. It visualizes how the pandemic grew across different countries in the world from February 15, 2020 (about one month prior to the US shutdown) until May 14, 2022 (a little over 2 years after the initial shutdown). Click the 'play' button below the date slider to see changes over time across different variables."),
      
      # Row 1: World map plot
      layout_columns(
        col_widths = c(9, 3),
        
        # Left: World map plot
        card(
          plotOutput("covidWorldMap", height = "400px")
        ),
        
        # Right: Map annotation text
        card(
          card_body(
            
            # Title for the annotations
            h4("Map Notes"),
            
            # List of annotations
            tags$ul(
              tags$li("Data is log-scaled for visability."),
              tags$li("White regions indicate missing data (NA values)."),
              tags$li("Values are normalized per 1 million people."),
            )
          )
        )
      ),
      
      # Row 2: Time series plot
      layout_columns(
        col_widths = c(9, 3),
        
        # Left: Time series
        card(
          plotOutput("covidTimeSeries", height = "350px")
        ),
        
        # Right: Time series annotation text
        card(
          card_body(
            
            # Title for the annotations
            h4("Time Series Notes"),
            
            # List of the annotations
            tags$ul(
              tags$li("Shows total global count of the raw variable selected."),
              tags$li("Some notable dates (especially if 'Active Cases' is selected):",
                      tags$ul( # Nested for indentation
                        tags$li("Jan. 2021:", tags$a(href = "https://en.wikipedia.org/wiki/SARS-CoV-2_Alpha_variant", "Alpha variant")),
                        tags$li("May 2021:", tags$a(href = "https://en.wikipedia.org/wiki/SARS-CoV-2_Delta_variant", "First Delta variant")), 
                        tags$li("Sept. 2021: Second Delta variant"),  # would use same wikipedia link as the first delta variant
                        tags$li("Feb. 2022:", tags$a(href = "https://en.wikipedia.org/wiki/SARS-CoV-2_Omicron_variant", "Omicron variant"), "(largest spike in active/new cases)"), 
                      )
              )
            )
          )
        )
      ),
      
      # Transition text from page 1 to page 2
      p(strong("Takeaway:"), " The pandemic grew at varying speeds across the globe and at varying speeds throughout time (due to different variants). Ultimately, it left few countries unharmed. Next, let's take a look at how a country's economic practices and economic health correlated with the pandemic's impact. Click on the 'Impact of Economic Factors' page at the top."),
      
      # Footer with data sources for page 1
      p(
        strong("Data Sources:"),
        "(1) COVID-19 Global Data - ", 
        tags$a(href = "https://www.kaggle.com/datasets/josephassaker/covid19-global-dataset/data?select=worldometer_coronavirus_daily_data.csv", "Kaggle COVID-19 Dataset", target = "_blank"),
        "(2) World Vector Map Data - ", 
        tags$a(href = "https://cran.r-project.org/web/packages/rnaturalearthdata/index.html", "rnaturalearthdata Package", target = "_blank")
      )
      
    )
  ),
  
  # Page 2: Impact of Economic Variables
  nav_panel(
    title = "Impact of Economic Factors",
    
    layout_sidebar(
      sidebar = sidebar(
        
        # User-input: whether to view the scatter plots with a by-region color 
        radioButtons(
          "by_region", 
          "Scatter plot view",
          choices = c("Overall", "By region"), 
          selected = "Overall"
        )
        
      ), 
      
      # Helper text for page 2
      p("This page compares two economic indicators from 2019 (pre-pandemic) with number of pandemic-related deaths as of May 14, 2022. Note that some countries were omitted from the plots for having missing values. The results may seem counter-intuitive when viewing the plots without regional distinctions. Click the 'By Region' button in the sidebar to reveal a more intuitive pattern."),
      
      # Row 1: GDP plot
      layout_columns(
        col_widths = c(3, 9), # specifying the width of each card in the first row
        
        # Left: Text to explain GDP per capita
        card(
          h4("GDP per capita"), 
          p("Average economic output per person in a country. Larger values typically correspond to a larger, healthier economy, and indicate a higher standard of living."), 
        ),
        
        # Right: Plotting GDP per capita 
        card(
          plotOutput("gdpPlot", height = "500px")
        )
      ),
      
      # Row 2: Physicians per 1000 plot
      layout_columns(
        col_widths = c(3, 9), # specifying the width of each card in the second row
        
        # Left: Text to explain the physicians per 1000 variable
        card(
          h4("Physicians per 1000 people"), 
          p("This variable can be interpreted in two ways:"), 
          tags$ul(
            tags$li("How well-equipped a country is to handle disease. The graph does not make sense with this interpretation, as a more equipped country should have less deaths."),
            tags$li("A country's capacity to record and document sicknesses/deaths. This interpretation can explain the counter-intuitive results in both graphs - poorer countries with less doctors don't actually have less deaths - they simply can't document as many deaths!")
          ),
        ),
        
        # Right: Plotting the physicians per 1000 variable
        card(
          plotOutput("physiciansPlot", height = "500px")
        )
      ), 
      
      # Takeaway text at bottom of page
      p(strong("Takeaway:"), "Examining the second plot - and the regional breakdowns - highlights an important insight about COVID-19 data quality: although poorer countries and regions appear to have fewer deaths than wealthier ones, this pattern may be misleading. Many lower-income countries lacked the physicians, resources, and infrastructure to fully document infections and deaths, leading to under-reported figures that do not reflect the true impact of the pandemic. This conclusion is similarly found in", tags$a("other research.", href="https://pubmed.ncbi.nlm.nih.gov/38902661/")),
      
      # Footer with data sources for page 2
      p(
        strong("Data Sources:"),
        "(1) COVID-19 Global Data - ", 
        tags$a(href = "https://www.kaggle.com/datasets/josephassaker/covid19-global-dataset/data?select=worldometer_coronavirus_daily_data.csv", "Kaggle COVID-19 Dataset", target = "_blank"),
        "(2) World Development Indicators - ", 
        tags$a(href = "https://cran.r-project.org/web/packages/WDI/index.html", "WDI Package", target = "_blank")
      )
      
    )
  )
)

### ------------- App Server ----------------

server <- function(input, output) {
  
  # Reactive element 1: Change the date for the given input by the slider 
  data_for_date <- reactive({
    world_covid_data %>%
      filter(date == input$date)
  })
  
  # Reactive element 2: Dynamic limits: recompute min/max for selected variable over the entire dataset
  var_limits <- reactive({
    
    # extracting the limits using the per 1M variables
    v_map <- paste0(input$var, "_per_1M") 
    c(
      min(world_covid_data[[v_map]], na.rm = TRUE),
      max(world_covid_data[[v_map]], na.rm = TRUE)
    )
  })
  
  ### Page 1 plots: World map and Time series plot
  
  # Plot 1: Mapping the selected variable by country over time -- shows spatial variation
  output$covidWorldMap <- renderPlot({
    
    # Currently selected variable 
    v_map <- paste0(input$var, "_per_1M")
    
    ggplot(data_for_date()) +
      geom_sf(aes(fill = .data[[v_map]])) + # selecting the variable for fill
      coord_sf() +
      scale_fill_gradient(
        low = "grey",          # grey if variable = minimum value
        high = "red3",         # red if variable = maximum value
        na.value = "white",    # white if variable = NA 
        trans = "log",         # log-transformation of the variable
        name = paste(names(var_labels)[var_labels == input$var], "per 1M\n(log-scale)"),         # dynamic legend title
        limits = var_limits(),        # dynamic legend limits 
      ) +
      labs(
        title = paste("**By-Country Growth**:", names(var_labels)[var_labels == input$var], "per 1M"),
      ) +
      theme_minimal(base_size = 14) +
      theme(
        legend.position = "right", 
        axis.text.x = element_blank(),            # Remove x-axis tick labels 
        axis.text.y = element_blank(),            # Remove y-axis tick labels 
        panel.grid.major = element_blank(),       # Remove all major gridlines
        plot.title = element_markdown(size = 20)  # make the title a markdown element
      )
  })
  
  # Plot 2: Time-series plot of the selected variable over time -- shows temporal variation
  output$covidTimeSeries <- renderPlot({
    
    # Extracting the variables name (raw variable, not per 1M)
    raw_var <- input$var
    
    # Creating the time-series dataframe
    ts_data <- world_covid_data %>%
      st_drop_geometry() %>% 
      group_by(date) %>% 
      summarize(
        total_val = sum(.data[[raw_var]], na.rm = TRUE),
        .groups = "drop"
      )
    
    # Only plotting dates before the input date 
    df <- ts_data %>% filter(date <= input$date)
    
    # Creating the plot 
    ggplot(df, aes(x = date, y = total_val)) +
      geom_line(size = 1.2, color = "red3") +
      scale_x_date(
        limits = c(   # Creating fixed limits for the x-axis of the plot
          min(world_covid_data$date, na.rm = TRUE), 
          max(world_covid_data$date, na.rm = TRUE)
        ), 
        date_labels = "%b %Y",        # Changing the layout of the dates on x-axis
        date_breaks = "3 months",     # Show a label every 3 months
      ) +
      scale_y_continuous(labels = scales::comma) + # formatting the y-axis labels
      labs(
        title = paste("**Global Growth**:", names(var_labels)[var_labels == raw_var]),
        x = "Date",
        y = names(var_labels)[var_labels == raw_var]
      ) +
      theme_minimal(base_size = 14) + 
      theme(
        panel.grid.minor.x = element_blank(),     # hiding the minor gridlines for x-axis
        panel.grid.minor.y = element_blank(),     # hiding the minor gridlines for y-axis
        plot.title = element_markdown(size = 20)  # make the title a markdown element
      )
    
  })
  
  ### Page 2 plots: GDP and Physicians per 1000 relationship with deaths per 1M
  
  # Plot 3: GDP vs COVID deaths (switches between overall and by-region)
  output$gdpPlot <- renderPlot({
    
    # GDP Plot: Overall version
    if (input$by_region == "Overall") {
      
      ggplot(econ_covid_merged, aes(x=gdp_per_cap, y=cumulative_total_deaths_per_1M)) +
        geom_point(
          color = "red3", 
          alpha = 0.5
        ) + 
        geom_smooth(   # creating a smoother 
          formula = "y~x", method = "loess",  # loess regression 
          se = FALSE, span = 2,  # no error bar, and not very wiggly
          color = "red3", 
          alpha = 0.75
        ) + 
        geom_text_repel(     # labeling the outliers in the data 
          data = outliers_gdp,
          aes(label = country),
          size = 4.5,
          color = "black",
          max.overlaps = Inf, 
          box.padding=0.6,
          min.segment.length=0, 
        ) +
        annotate(
          geom = "text",         # text geom
          color = "black",       # color is black
          size = 5,              # size of the annotation
          x = 15000, y = 40,     # location of the annotation
          hjust = 0,             # left-alignment
          label = "Counter-intuitive result:\nMore wealth = more deaths? Only\npast a GDP of $10,000 do deaths\ndecrease with GDP."
        ) + 
        scale_x_continuous(
          trans = "log10",                            # log transforming the x-axis
          name = "GDP per capita (log scale)",        # x-axis labels
          breaks = c(1000, 10000, 100000),            # x-axis breaks
          labels = scales::label_dollar(accuracy=1),  # x-axis label formatting 
        ) + 
        scale_y_continuous(
          trans = "log10",    # log transformation of the y-axis (automatically handles labels and breaks)
          name = "Cumulative deaths per 1M as \nof 5/14/2022 (log scale)",  # y-axis title
        ) + 
        labs(
          title = "Countries' COVID-19 deaths vs. GDP per capita\n(outliers labeled)"
        ) + 
        theme_minimal(base_size = 14) + 
        theme(
          plot.title = element_text(size = 20)
        ) 
      
    # GDP Plot: By region version
    } else {
      
      ggplot(econ_covid_merged, aes(x=gdp_per_cap, y=cumulative_total_deaths_per_1M, color = region_un)) +
        geom_point(
          alpha = 0.5
        ) + 
        geom_smooth(   # creating a smoother 
          formula = "y~x", method = "loess",  # loess regression 
          se = FALSE, span = 2,  # no error bar, and not very wiggly
          alpha = 0.75
        ) + 
        geom_text_repel(        # labeling the outliers in the data 
          data = outliers_gdp,
          aes(label = country),
          size = 4.5,
          color = "black",
          max.overlaps = Inf, 
          box.padding=0.6,
          min.segment.length=0, 
        ) +
        annotate(
          geom = "text",         # text geom
          color = "black",       # color is black
          size = 5,              # size of the annotation
          x = 15000, y = 40,     # location of the annotation
          hjust = 0,             # left-alignment
          label = "Very clear regional clusters\nwith distinct trends.\nResults make more sense!"
        ) + 
        scale_x_continuous(
          trans = "log10",                            # log transforming the x-axis
          name = "GDP per capita (log scale)",        # x-axis labels
          breaks = c(1000, 10000, 100000),            # x-axis breaks
          labels = scales::label_dollar(accuracy=1),  # x-axis label formatting 
        ) + 
        scale_y_continuous(
          trans = "log10",    # log transformation of the y-axis (automatically handles labels and breaks)
          name = "Cumulative deaths per 1M as \nof 5/14/2022 (log scale)",  # y-axis title
        ) + 
        labs(
          color = "UN Region", 
          title = "Countries' COVID-19 deaths vs. GDP per capita\n(by region, outliers labeled)"
        ) + 
        theme_minimal(base_size = 14) + 
        theme(
          plot.title = element_text(size = 20)
        )
      
    }
    
  })
  
  # Plot 4: Physicians vs COVID deaths (switches between overall and by-region)
  output$physiciansPlot <- renderPlot({
    
    # Physicians Plot: Overall version
    if (input$by_region == "Overall") {
      
      ggplot(econ_covid_merged, aes(x=physicians, y=cumulative_total_deaths_per_1M)) +
        geom_point(
          color = "red3", 
          alpha = 0.5
        ) + 
        geom_smooth(   # creating a smoother 
          formula = "y~x", method = "loess",  # loess regression 
          se = FALSE, span = 2,  # no error bar, and not very wiggly
          color = "red3", 
          alpha = 0.75
        ) + 
        geom_text_repel(     # labeling the outliers in the data 
          data = outliers_physicians,
          aes(label = country),
          size = 4.5,
          color = "black",
          max.overlaps = Inf, 
          box.padding=0.6,
          min.segment.length=0, 
        ) +
        annotate(
          geom = "text",         # text geom
          color = "black",       # color is black
          size = 5,              # size of the annotation
          x = 0.03, y = 1000,    # location of the annotation
          hjust = 0,             # left-alignment
          label = "Counter-intuitive result:\nMore doctors = more deaths?"
        ) + 
        scale_x_continuous(
          name = "Physicians per 1000 people (log scale)",        # x-axis labels
          trans = "log10"                                         # log transformation
        ) + 
        scale_y_continuous(
          trans = "log10",    # log transformation of the y-axis (automatically handles labels and breaks)
          name = "Cumulative deaths per 1M as \nof 5/14/2022 (log scale)",  # y-axis title
        ) + 
        labs(
          title = "Countries' COVID-19 deaths vs. Number of Physicians per 1000 people\n(outliers labeled)"
        ) + 
        theme_minimal(base_size = 14) + 
        theme(
          plot.title = element_text(size = 20)
        ) 
      
    # Physicians Plot: By region version
    } else {
      
      ggplot(econ_covid_merged, aes(x=physicians, y=cumulative_total_deaths_per_1M, color = region_un)) +
        geom_point(
          alpha = 0.5
        ) + 
        geom_smooth(   # creating a smoother 
          formula = "y~x", method = "loess",  # loess regression 
          se = FALSE, span = 2,  # no error bar; not very wiggly line
          alpha = 0.75
        ) + 
        geom_text_repel(     # labeling the outliers in the data 
          data = outliers_physicians,
          aes(label = country),
          size = 4.5,
          color = "black",
          max.overlaps = Inf, 
          box.padding=0.6,
          min.segment.length=0, 
        ) +
        annotate(
          geom = "text",         # text geom
          color = "black",       # color is black
          size = 5,              # size of the annotation
          x = 0.03, y = 1000,    # location of the annotation
          hjust = 0,             # left-alignment
          label = "Each region has a distinct\ntrend (or lack thereof) that can\nbe explained!"
        ) + 
        scale_x_continuous(
          name = "Physicians per 1000 people (log scale)",        # x-axis labels
          trans = "log10"
        ) + 
        scale_y_continuous(
          trans = "log10",    # log transformation of the y-axis (automatically handles labels and breaks)
          name = "Cumulative deaths per 1M as \nof 5/14/2022 (log scale)",  # y-axis title
        ) + 
        labs(
          color = "UN Region", 
          title = "Countries' COVID-19 deaths vs. Number of Physicians per 1000 people\n(by region, outliers labeled)"
        ) + 
        theme_minimal(base_size = 14) + 
        theme(
          plot.title = element_text(size = 20)
        ) 
    }
    
  })
  
  
}

# Building the finalized app
shinyApp(ui, server)

