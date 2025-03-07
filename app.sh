#!/bin/bash

# Get the directory of the script
script_dir=$(dirname "$0")

venv_dir="$script_dir/.venv"

# Check if Python 3 is installed
if command -v python3 &>/dev/null; then
    echo "Python 3 is already installed."
else
    echo "Python 3 is not installed. Installing..."
    # Update package list and install Python 3
    sudo apt update
    sudo apt install python3
    echo "Python 3 has been installed."
fi

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

#check if tkinter is installed
if ! python3 -c "import tkinter" &>/dev/null; then
    echo "tkinter in not installed. Installing now.."
    pip3 install tk
else 
    echo "tkinter is already installed."
fi

#check if psutil is installed
if ! python3 -c "import psutil" &>/dev/null; then
    echo "psutil in not installed. Installing now.."
    pip3 install psutil
else 
    echo "psutil is already installed."
fi

# Check if paho-mqtt is installed
if ! python3 -c "import paho.mqtt" &>/dev/null; then
    echo "paho-mqtt is not installed. Installing now..."

    # Install paho-mqtt using pip
    pip3 install "paho-mqtt<2.0.0"
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
from threading import Thread
import time

import struct
import serial
import serial.tools.list_ports

import paho.mqtt.client as mqtt
import psutil
import json
import ssl

from tkinter import ttk
from datetime import datetime

import socket

def get_active_network():
    eth_status = wifi_status =False
    interfaces = psutil.net_if_stats()
    for interface, stats in interfaces.items():
        if stats.isup:  # Check if interface is up
            if "Ethernet" in interface or "en" in interface:  # Ethernet names
                eth_status = True
            if "Wi-Fi" in interface or "wl" in interface:  # Wi-Fi names
                wifi_status = True
    return eth_status, wifi_status

def has_internet():
    try:
        socket.create_connection(("8.8.8.8", 53), timeout=3)
        return True
    except OSError:
        return False

def get_mac_addresses():
    """Scans all network interfaces and find the WiFi one and use WiFi Mac for Client ID."""
    addrs = psutil.net_if_addrs()
    for interface, addr_list in addrs.items():
        for addr in addr_list:
            if addr.family == psutil.AF_LINK:  # MAC Address
                if 'wl' in interface or 'Wi-Fi' in interface:
                    return addr.address.upper()
    return None

class MQTTClient:

    def __init__(self):
        try:
            with open("config.json","r") as file:
                data = json.load(file)
        except:
            with open("config.json","w") as file:
                data = {"server": "iot.moe.gov.kh","port": 8883,"username":"iot","password":"&j?/yO^{c[?+ub","userId": get_mac_addresses(),"topic": "mqtt/sensor/routing","security":True}
                json.dump(data,file,indent=4)
        self.broker = data["server"]
        self.port = data["port"]
        self.userId = data["userId"]
        self.clientId = get_mac_addresses() 
        self.client = mqtt.Client(client_id=self.clientId, userdata=None, protocol=mqtt.MQTTv311)
        self.username = data["username"]
        self.password = data["password"]
        self.client.on_connect = self.on_connect
        self.client.on_message = self.on_message
        self.client.on_disconnect = self.on_disconnect
        self.topic_send = data["topic"]
        self.topic =[]

        self.set_user_pass(self.username, self.password)
        if (data["security"]):
            self.setInscure()
        self.connect()
        
    def is_connected(self):
        return self.client.is_connected()
    def on_connect(self, client, userdata, flags, rc):
        if rc == 0:
            print("Connected to MQTT Broker!")
            for t in self.topic:
                client.subscribe(t)
            # client.subscribe(self.topic)
            while True:
                file_path = "buffer_data.jsonl"
                try:
                    with open(file_path, "r") as file:
                        lines = file.readlines()  # Read all lines
                except :
                    with open(file_path, 'w') as file:
                        pass
                    break
                if not lines:  # Check if the file is empty
                    break
                
                first_line = lines[0].strip()  # Get the first line
                try:
                    data = json.loads(first_line)  # Parse JSON
                    if(self.publish_dict(data)):
                        with open("sent_buffer_data.jsonl","a") as file1:
                            json.dump(data,file1)
                            file1.write("\n")
                    else:
                        break
                except json.JSONDecodeError:
                    print("Error: Invalid JSON in the first line.")
                    break
                
                # Rewrite the file without the first line
                with open(file_path, "w") as file:
                    file.writelines(lines[1:])  # Write remaining lines

                time.sleep(0.1)
        else:
            print("Failed to connect, return code %d\n", rc)

    def add_subscribe(self, topic):
        if self.client.is_connected():
            self.client.subscribe(topic)
            self.topic.append(topic)
        else:
            self.topic.append(topic)

    def on_message(self, client, userdata, msg):
        print(f"Message received: {msg.topic} {msg.payload}")

    def on_disconnect(self, client, userdata, rc):
        print(f"Disconnected with result code {rc}")
        while not client.is_connected():
            try:
                client.reconnect()
                time.sleep(5)
            except Exception as e:
                time.sleep(5)
    def set_user_pass(self, username, password):
        self.client.username_pw_set(username, password)

    def setInscure(self):
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        self.client.tls_set_context(context)

    def connect(self):
        self.setup_Connection = False
        self.MqttThread = Thread(target=self.setupConnection)
        self.MqttThread.start()
    def setupConnection(self):
        while not self.setup_Connection:
            try:
                
                self.client.connect(self.broker, self.port, 15)
                self.client.loop_start()
                self.setup_Connection = True
                print("mqtt setup succes!!")
            except Exception as e:
                time.sleep(5)
    def publish(self,ph, temp, cod, ss, waterflow):
        payload = {
            "payload": {
                "id": self.clientId,
                "name": self.userId,
                "fields": [
                    {
                        "ph": ph,
                        "temp": temp,
                        "cod": cod,
                        "ss": ss,
                        "waterflow": waterflow,
                        "timestamp": round(time.time())    # Unix timestamp
                    }
                ]
            }
        }
        
        with open("data.jsonl", "a") as file:
            data = payload["payload"]["fields"][0]
            json.dump(data, file)
            file.write("\n")
        self.publish_dict(payload)
    
    def publish_dict(self,payload):
        json_payload = json.dumps(payload)
        if self.client.is_connected():  # Check if connected
            self.client.publish(self.topic_send, str(json_payload))
        else:
            with open("buffer_data.jsonl","a") as file:
                json.dump(payload,file)
                file.write('\n')
            return False
        return True


class RS485:
    def __init__(self, baudrate=9600, timeout=1):
        self.port = None
        self.ser = None
        self.burate = baudrate
        self.timeout = timeout
        self.ser = self.setup()

    def setup(self):
        if self.port is None:
            return None
        try:
            self.ser = serial.Serial(self.port, self.burate, timeout=self.timeout)
        except serial.SerialException:
            self.ser = None
        return self.ser

    def ph_sensor(self):
        sendData = [0x0A, 0x03, 0x00, 0x01, 0x00, 0x02, 0x94, 0xB0]
        self.ser.write(sendData)
        self.ser.flush()

        start_time = time.time()
        while self.ser.in_waiting < 9 and (time.time() - start_time) < 1:
            time.sleep(0.01)

        if self.ser.in_waiting >= 9:
            raw_data = self.ser.read(9)
            ph_value = bytes([raw_data[5], raw_data[6], raw_data[3], raw_data[4]])
            value = round(struct.unpack('>f', ph_value)[0], 2)
            return value

        return None

    def temp_sensor(self):
        sendData = [0x0A, 0x03, 0x00, 0x03, 0x00, 0x02, 0x35, 0x70]
        self.ser.write(sendData)
        self.ser.flush()

        start_time = time.time()
        while self.ser.in_waiting < 9 and (time.time() - start_time) < 1:
            time.sleep(0.01)

        if self.ser.in_waiting >= 9:
            raw_data = self.ser.read(9)
            temp_value = bytes([raw_data[5], raw_data[6], raw_data[3], raw_data[4]])
            value = round(struct.unpack('>f', temp_value)[0], 2)
            return value

        return None

    def cod_sensor(self):
        sendData = bytes([0x22, 0x03, 0x26, 0x00, 0x00, 0x06, 0xC9, 0xD3])
        self.ser.write(sendData)
        self.ser.flush()

        start_time = time.time()
        while self.ser.in_waiting < 17 and (time.time() - start_time) < 1:
            time.sleep(0.01)

        if self.ser.in_waiting >= 17:
            raw_data = self.ser.read(17)
            cod_data = bytes([raw_data[10], raw_data[9], raw_data[8], raw_data[7]])
            toc_data = bytes([raw_data[14], raw_data[13], raw_data[12], raw_data[11]])

            cod = round(struct.unpack('>f', cod_data)[0], 2)
            toc = round(struct.unpack('>f', toc_data)[0], 2)
            return cod, toc

        return None, None

    def tss_sensor(self):
        sendData = [0x0E, 0x03, 0x2C, 0x00, 0x00, 0x04, 0x4C, 0x66]
        self.ser.write(sendData)
        self.ser.flush()

        start_time = time.time()
        while self.ser.in_waiting < 13 and (time.time() - start_time) < 1:
            time.sleep(0.01)

        if self.ser.in_waiting >= 13:
            raw_data = self.ser.read(13)
            tss_data = bytes([raw_data[10], raw_data[9], raw_data[8], raw_data[7]])
            value = round(struct.unpack('>f', tss_data)[0], 2)
            return value

        return None
    
    def check_serial(self):
        ports = serial.tools.list_ports.comports()
        self.port = None
        for port, desc, hwid in sorted(ports):
            if "3-1" in hwid or "3-2" in hwid:
                if "PID=1A86:7523" in hwid:  # pid: 1A86, vid: 7523 is code for chip CH340 on RS485 module(RS485)
                    self.port = port
                    return True
        return False

def table(root):
    file_path = "data.jsonl"

    def load_data():
        try:
            with open(file_path, "r", encoding="utf-8") as file:
                data = [json.loads(line) for line in file]
                return data[::-1]
        except Exception as e:
            return []

    def refresh_table():
        # Clear existing data
        for item in tree.get_children():
            tree.delete(item)

        # Load new data
        json_data = load_data()
        # Insert data into the table with row numbers
        timestamp =json_data[0]["timestamp"]
        for i, entry in enumerate(json_data, start=1):
            try:
                fields = entry
                tree.insert("", "end", values=(
                    datetime.fromtimestamp(fields["timestamp"]).strftime('%Y-%m-%d %H:%M:%S'),
                    fields["ph"], fields["temp"], fields["cod"],
                    fields["ss"], fields["waterflow"]
                ))
            except KeyError as e:
                print(f"Missing key in JSON entry: {e}")
        delay = round(timestamp+31 -time.time() )
        if delay <=0 :
            delay = 30
        # Schedule the next refresh
        root.after(delay*1000,refresh_table)  # Refresh every 10 seconds

    # GUI Setup
    root.title("Sensor Data Monitor")
    screen_width = root.winfo_screenwidth()
    screen_height = root.winfo_screenheight()

    # Set the window to cover the full screen size
    root.geometry(f"{screen_width}x{screen_height}")

    # Create a frame for the table and scrollbar
    frame = tk.Frame(root)
    frame.pack(fill="both", expand=True)

    # Add a scrollbar
    tree_scroll = tk.Scrollbar(frame)
    tree_scroll.pack(side="right", fill="y")

    # Table setup with numbering column
    columns = ("Date-Time", "pH", "Temperature", "COD", "SS", "Waterflow")
    tree = ttk.Treeview(frame, columns=columns, show="headings", yscrollcommand=tree_scroll.set, height=30)

    # Configure the style for the Treeview
    style = ttk.Style()
    style.configure("Treeview.Heading", font=("Arial", 10, "bold"))  # Header font
    style.configure("Treeview", font=("Arial", 8))  # Cell font

    for col in columns:
        tree.heading(col, text=col)
        tree.column(col, anchor="center")

    # Attach scrollbar to the table
    tree_scroll.config(command=tree.yview)

    tree.pack(fill="both", expand=True)

    # Initial load of data
    refresh_table()

    root.bind("<Escape>", lambda event: root.destroy())

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
                                    font=("Arial", 23, "bold"), fg="white", bg="#2a2a2a")
        self.title_label.pack(pady=5)

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

        self.history_button = self.create_button("Table",cmd= self.update_table)
        self.graph_button = self.create_button("Graph")
        self.settings_button = self.create_button("Settings")
        self.about_button = self.create_button("About Me",cmd = self.exit)

        self.history_button.grid(row=0, column=0, padx=0, pady=5, sticky="nsew")
        self.graph_button.grid(row=1, column=0, padx=0, pady=5, sticky="nsew")
        self.settings_button.grid(row=2, column=0, padx=0, pady=5, sticky="nsew")
        self.about_button.grid(row=3, column=0, padx=0, pady=5, sticky="nsew")

        #create frame for status
        self.status_frame = tk.Frame(self.root, bg="#f0f0f0")
        self.status_frame.grid(row=2,column=0 ,sticky= "nsew", pady= 5 )
        #self.status_frame.pack(fill="x", pady=20)

        self.Eth_led = self.create_led("ETH")
        self.WiFi_led = self.create_led("Wi-Fi")
        self.server_led = self.create_led("Server")
        self.port_led = self.create_led("Port")

        # Start a thread to simulate data updates
        self.screenInterval = 30
        self.portInterval = 1

        self.fush  = False
        
        self.reader = RS485()
        self.ph = self.tss = self.cod = self.toc = self.temp = self.waterflow = None
        self.mqtt_client = MQTTClient()
        self.running = True
        self.running = True
        try:
            self.update_thread = Thread(target=self.update_screen,daemon= True)
            self.data_thread = Thread(target=self.update_data, daemon=True)
            self.status_thread = Thread(target=self.update_status, daemon= True)
            self.status_thread.start()
            self.data_thread.start()
            self.update_thread.start()
        except Exception as e:
            print(e)

    def create_text_box(self, initial_text):
        frame = tk.Frame(self.data_frame, bg="#3f9fd8", bd=3, relief="solid")
        text_box = tk.Text(frame, font=("Arial", 20), bg="white", fg="black", wrap=tk.WORD, bd=5)

        text_box.insert(tk.END, "\n" +initial_text)
        text_box.config(state=tk.DISABLED)
        text_box.pack(fill=tk.BOTH, expand=True, padx=5, pady=5,anchor= "center",side = "right")       
        frame.pack_propagate(False)
        return frame
    def create_button(self, text,cmd = None):
        button = tk.Button(self.button_frame, text=text, font=("Arial", 18, "bold"), bg="#4CAF50", fg="white", width=4, height=2,bd = 5,activebackground= "#4CAF00",command= cmd)
        return button

    def create_led(self,text):
        label = tk.Label(self.status_frame, text=f" {text}:", font=("Arial", 11), bg="#f0f0f0")
        label.pack(side="left", padx=1)

        led = tk.Canvas(self.status_frame, width=20, height=20, bg="#f0f0f0", highlightthickness=0)
        led.pack(side="left", padx=5)
        led.create_oval(2, 2, 18, 18, fill="red", tags="led")  # Default: Red
        return led
    def exit(self):
        self.root.destroy()
    
    # edit text 
    def update_text_box(self, text_box, new_data):
        """Update the content of a text box."""
        text_box.config(state=tk.NORMAL)  # Enable editing
        text_box.delete(1.0, tk.END)  # Clear the existing content
        text_box.insert(tk.END, "\n"+new_data)  # Insert the new data
        text_box.config(state=tk.DISABLED)  # Make it read-only again
    
    def update_led(self, canvas, color):
        """Update LED color based on status."""
        canvas.itemconfig("led", fill=color)
    def update_screen(self):
        try:
            time.sleep(self.screenInterval/2)
            while self.running:
                # recieve data from sensors every 30 seconds self.screenInterval = 30
                try:
                    start = time.time()
                    ph = self.ph
                    tss = self.tss
                    cod = self.cod
                    toc = self.toc
                    temp = self.temp
                    waterflow = self.waterflow
                    # Update each text box with the new data
                    self.update_text_box(self.ph_text_box.winfo_children()[0], f"pH: {ph}")
                    self.update_text_box(self.tss_text_box.winfo_children()[0], f"TSS: {tss} mg/L")
                    self.update_text_box(self.cod_text_box.winfo_children()[0], f"COD: {cod} mg/L")
                    self.update_text_box(self.toc_text_box.winfo_children()[0], f"TOC: {toc} mg/L")
                    self.update_text_box(self.temp_text_box.winfo_children()[0], f"Temperature: {temp}°C")
                    self.update_text_box(self.waterflow_text_box.winfo_children()[0], f"Water Flow: {waterflow} L/s")
                    if ph is None:
                        ph = 0.0
                    if tss is None: 
                        tss = 0.0
                    if cod is None: 
                        cod = 0.0
                    if toc is None:
                        toc = 0.0
                    if temp is None:
                        temp = 0.0
                    if waterflow is None:                  
                        waterflow = 0.0
                    self.mqtt_client.publish(ph, temp, cod, tss, waterflow)
                    end =  time.time()
                    delay = self.screenInterval - (end - start)
                    time.sleep(delay)
                except Exception as e:
                    print(e)
                    self.running = False
        except Exception as e:
            self.running =False
            print(e)
    def update_data(self):
        time.sleep(0.5)
        while self.running:
            start = time.time()
            self.ph = self.tss = self.cod = self.toc = self.temp = self.waterflow = None
            try :
                if self.reader.ser is None:
                    self.reader.ser = self.reader.setup()
                if self.reader.ser is not None:
                    if self.reader.ser.is_open:
                        try:
                            self.fush = True
                            self.ph = self.reader.ph_sensor()
                            time.sleep(1)
                            self.tss = self.reader.tss_sensor()
                            time.sleep(1)
                            self.cod, self.toc = self.reader.cod_sensor()
                            time.sleep(1)
                            self.temp = self.reader.temp_sensor()
                            time.sleep(1)
                            self.waterflow = None
                            time.sleep(1)
                            self.fush = False
                        except Exception as e:
                            self.reader.ser.close()  # Close the serial port
                            self.reader.ser = None # Reset the serial port object
                            self.fush = False
                end = time.time()
                delay = self.screenInterval - (end -start)
                time.sleep(delay)
            except Exception as e:
                print(e)

    def update_status(self):
        while self.running:
            try:
                if self.fush:
                    time.sleep(2)
                    continue
                led_eth = led_wifi = led_internet = led_mqtt = led_port = False
                        
                led_port = self.reader.check_serial()
                led_eth, led_wifi = get_active_network()
                led_internet = has_internet()
                led_mqtt = self.mqtt_client.is_connected()
                if led_eth and led_internet:
                    eth_color = "green"
                elif led_eth:
                    eth_color = "orange"
                else:
                    eth_color = "red"
                        
                if led_wifi and led_internet:
                    wifi_color = "green"
                elif led_wifi:
                    wifi_color = "orange"
                else:
                    wifi_color = "red"
                self.update_led(self.Eth_led, eth_color)
                self.update_led(self.WiFi_led, wifi_color)
                self.update_led(self.server_led, color = "green" if led_mqtt else "red")
                self.update_led(self.port_led, color = "green" if led_port else "red")
            except Exception as e:
                print(e)
            time.sleep(2)
    
    def update_table(self):
        new_screen = tk.Toplevel(self.root)
        table(new_screen)
if __name__ == "__main__":
    root = tk.Tk()
    app = DataDisplayApp(root)
    try:
        root.mainloop()
    except KeyboardInterrupt:
        pass
EOF