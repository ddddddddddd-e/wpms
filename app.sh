#!/bin/bash

# Get the directory of the script
script_dir=$(dirname "$0")

venv_dir="$script_dir/.venv"

#!/bin/bash

# Check if Python 3 is installed
if command -v python3 &>/dev/null; then
    echo "Python 3 is already installed."
else
    echo "Python 3 is not installed. Installing..."
    # Update package list and install Python 3
    sudo apt update
    sudo apt install python3 -y
    echo "Python 3 has been installed."
fi

# Check if .venv directory exists
if [ -d "$venv_dir" ]; then
    echo ".venv is found. Activating the virtual environment."
    # Activate the virtual environment
    source "$venv_dir/bin/activate"
else
    echo ".venv not found. Creating a new virtual environment."
    # Create a new virtual environment
    python3 -m venv "$venv_dir"
    # Activate the virtual environment
    source "$venv_dir/bin/activate"
fi

# Check if paho-mqtt is installed
if ! python3 -c "import paho.mqtt" &>/dev/null; then
    echo "paho-mqtt is not installed. Installing now..."

    # Install paho-mqtt using pip
    pip3 install paho-mqtt
else
    echo "paho-mqtt is already installed."
fi

if ! python3 -c "import serial" &>/dev/null; then
    echo "pyserial is not installed. Installing now..."

    # Install paho-mqtt using pip
    pip3 install pyserial
else
    echo "pyserial is already installed."
fi


# Specify the file you want to create in the same directory
file_path="$script_dir/yourfile.txt"

# Set the environment variable for Python to access
export FILE_PATH="$file_path"



python3 - <<EOF
import tkinter as tk

class DataDisplayApp:
    def __init__(self, root):
        print("screen started")
        self.root = root
        self.root.title("Environmental Data Display")
        self.root.attributes('-fullscreen', True)
        self.root.config(bg="#f0f0f0")
        self.root.grid_rowconfigure(0, weight=1)  # Allow vertical expansion
        self.root.grid_rowconfigure(1, weight=5)  # Allow vertical expansion
        self.root.grid_rowconfigure(2, weight=1)  # Allow vertical expansion
        self.root.grid_columnconfigure(0, weight=1)  # Allow vertical expansion

        

        # Header Frame
        self.header_frame = tk.Frame(self.root, bg="#2a2a2a")
        self.header_frame.grid(row = 0,column=0,sticky="nsew")
        #self.header_frame.pack(fill="both", pady=5)
        self.title_label = tk.Label(self.header_frame, text="Water Quality Monitoring System", 
                                    font=("Arial", 50, "bold"), fg="white", bg="#2a2a2a")
        self.title_label.pack(pady=10)

        # Main Frame (2/3 data display, 1/3 buttons)
        self.main_frame = tk.Frame(self.root, bg="#f0f0f0")
        self.main_frame.grid(row= 1, column= 0,sticky="nsew", padx= 20, pady= 20)
        #self.main_frame.pack(expand=True, fill="both", padx=20, pady=20)

        # Configure grid layout for 8:1 ratio

        self.main_frame.grid_columnconfigure(0, weight=8)  # Data Frame (2/3)
        self.main_frame.grid_columnconfigure(1, weight=1)  # Button Frame (1/3)
        self.main_frame.grid_rowconfigure(0, weight=1)  # Allow vertical expansion

        # Data Frame (2/3 of screen)
        self.data_frame = tk.Frame(self.main_frame, bg="#f0f0f0")
        self.data_frame.grid(row=0, column=0, sticky="nsew", pady=10)

        self.ph_text_box = self.create_text_box("pH: 0.0")
        self.tss_text_box = self.create_text_box("TSS: 0.0mg/L")
        self.cod_text_box = self.create_text_box("COD: 0.0mg/L")
        self.toc_text_box = self.create_text_box("TOC: 0.0mg/L")
        self.temp_text_box = self.create_text_box("Temperature: 0.0°C")
        self.waterflow_text_box = self.create_text_box("Water Flow: 0.0 L/s")

        self.ph_text_box.grid(row=0, column=0, padx=10, pady=10, sticky="nsew")
        self.tss_text_box.grid(row=0, column=1, padx=10, pady=10, sticky="nsew")
        self.cod_text_box.grid(row=1, column=0, padx=10, pady=10, sticky="nsew")
        self.toc_text_box.grid(row=1, column=1, padx=10, pady=10, sticky="nsew")
        self.temp_text_box.grid(row=2, column=0, padx=10, pady=10, sticky="nsew")
        self.waterflow_text_box.grid(row=2, column=1, padx=10, pady=10, sticky="nsew")

        self.data_frame.grid_rowconfigure([0, 1, 2], weight=1)
        self.data_frame.grid_columnconfigure([0, 1], weight=1)

        # Button Frame (1/3 of screen)
        self.button_frame = tk.Frame(self.main_frame, bg="#f0f0f0")
        self.button_frame.grid(row=0, column=1, sticky="nsew")
        self.button_frame.grid_rowconfigure([0, 1, 2, 3], weight=1)
        self.button_frame.grid_columnconfigure(0, weight=1) 

        self.history_button = self.create_button("Table")
        self.graph_button = self.create_button("Graph")
        self.settings_button = self.create_button("Settings")
        self.about_button = self.create_button("About Me")

        self.history_button.grid(row=0, column=0, padx=0, pady=30, sticky="nsew")
        self.graph_button.grid(row=1, column=0, padx=0, pady=30, sticky="nsew")
        self.settings_button.grid(row=2, column=0, padx=0, pady=30, sticky="nsew")
        self.about_button.grid(row=3, column=0, padx=0, pady=30, sticky="nsew")

        #create frame for status
        self.status_frame = tk.Frame(self.root, bg="#f0f0f0", height=50)
        self.status_frame.grid(row=2,column=0 ,sticky= "nsew", pady= 20 )
        #self.status_frame.pack(fill="x", pady=20)

        self.Eth_led = self.create_led("ETH")
        self.WiFi_led = self.create_led("Wi-Fi")
        self.server_led = self.create_led("Server")
        self.port_led = self.create_led("Port")


    def create_text_box(self, initial_text):
        frame = tk.Frame(self.data_frame, bg="#3f9fd8", bd=3, relief="solid")
        text_box = tk.Text(frame, font=("Arial", 46), bg="white", fg="black", wrap=tk.WORD, bd=5)

        text_box.insert(tk.END, "\n" +initial_text)
        text_box.config(state=tk.DISABLED)
        text_box.pack(fill=tk.BOTH, expand=True, padx=5, pady=5,anchor= "center",side = "right")       
        frame.pack_propagate(False)
        return frame
    def create_button(self, text,cmd = None):
        button = tk.Button(self.button_frame, text=text, font=("Arial", 18, "bold"), bg="#4CAF50", fg="white", width=4, height=2,bd = 5,activebackground= "#4CAF00",command= cmd)
        return button

    def create_led(self,text):
        label = tk.Label(self.status_frame, text=f" {text}:", font=("Arial", 18), bg="#f0f0f0")
        label.pack(side="left", padx=1)

        led = tk.Canvas(self.status_frame, width=20, height=20, bg="#f0f0f0", highlightthickness=0)
        led.pack(side="left", padx=5)
        led.create_oval(2, 2, 18, 18, fill="red", tags="led")  # Default: Red
        return led

if __name__ == "__main__":
    root = tk.Tk()
    app = DataDisplayApp(root)
    try:
        root.mainloop()
    except KeyboardInterrupt:
        pass
EOF