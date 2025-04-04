#!/bin/bash

# Get the directory of the script
script_dir="/home/kickpi/Desktop/wpms/"

file_path="$script_dir".

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
import random

from tkinter import ttk
from tkcalendar import DateEntry  
from datetime import datetime, timedelta

import numpy as np
from scipy.interpolate import interp1d
import matplotlib.dates as mdates

from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from matplotlib.figure import Figure 

import calendar
import mplcursors

import socket
import os

dir = os.getenv('FILE_PATH')
if dir is None:
    dir = "/home/user/PycharmProjects/WPMS"
def get_active_network():
    eth_status = wifi_status =False
    interfaces = psutil.net_if_stats()
    for interface, stats in interfaces.items():
        if stats.isup:  # Check if interface is up
            if "Ethernet" in interface or "en" in interface:  # Ethernet names
                eth_status = True
            if "Wi-Fi" in interface or "wl" in interface or "p2p" in interface:  # Wi-Fi names
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
                if 'wl' in interface or 'Wi-Fi' in interface :
                    return addr.address.upper()
    return None

class MQTTClient:

    def __init__(self):
        global dir
        try:
            with open( dir +"/config.json","r") as file:
                data = json.load(file)
        except:
            with open(dir+ "/config.json","w") as file:
                data = {"server": "iot.moe.gov.kh","port": 8883,"username":"iot","password":"&j?/yO^{c[?+ub","userId": get_mac_addresses(),"topic": "test","security":True}
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
            global dir
            file_path = dir + "/buffer_data.jsonl"
            buffer_path = dir + "/sent_buffer_data.jsonl"
            while True:
                
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
                        with open(buffer_path,"a") as file1:
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
        self.MqttThread = Thread(target=self.setupConnection,daemon= True)
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
    
    def publish_dict(self,payload):
        json_payload = json.dumps(payload)
        if self.client.is_connected():  # Check if connected
            self.client.publish(self.topic_send, str(json_payload))
        else:
            global dir
            with open(dir + "/buffer_data.jsonl","a") as file:
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

class Table():
    def __init__(self, root):
        self.root = root
        self.file_path = "data.jsonl"
        self.root.title("Sensor Data Monitor")
        screen_width = self.root.winfo_screenwidth()
        screen_height = self.root.winfo_screenheight()

        # Set the window to cover the full screen size
        self.root.geometry(f"{screen_width}x{screen_height}")
        
        # Frame for Controls (Calendar + Button)
        self.control_frame = tk.Frame(self.root)
        self.control_frame.pack(fill='x', pady=3)

        # Calendar Input
        tk.Label(self.control_frame, text="Select Date:").pack(side="left", padx=5)
        self.date_entry = DateEntry(self.control_frame, width=12, background="blue", foreground="white", date_pattern="dd/mm/y")
        self.date_entry.pack(side="left", padx=5)

        # Refresh Button
        self.refresh_btn = tk.Button(self.control_frame, text="Refresh", command=self.refresh_table)
        self.refresh_btn.pack(side="left", padx=5)

        # Table Frame
        self.frame = tk.Frame(root)
        self.frame.pack(fill="both", expand=True)

        # Scrollbar
        self.tree_scroll = tk.Scrollbar(self.frame)
        self.tree_scroll.pack(side="right", fill="y")

        # Table Setup
        self.columns = ("Date-Time", "pH", "Temperature", "COD", "SS", "Waterflow")
        self.tree = ttk.Treeview(self.frame, columns=self.columns,show="headings", yscrollcommand=self.tree_scroll.set)

        # Configure Table Headers
        for col in self.columns:
            self.tree.heading(col, text=col)
            self.tree.column(col, anchor="center",)

        # Attach the Scrollbar to the Treeview
        self.tree_scroll.config(command=self.tree.yview)
        self.tree.pack(fill="both", expand=True)
        self.last = 500
        
        self.tree.bind("<Motion>", self.on_touch_scroll)  

        # Initial Load
        self.refresh_table()

        root.bind("<Escape>", lambda event: root.destroy())
        self.date_entry.bind("<<DateEntrySelected>>", self.auto_refresh)


    def load_data(self,selected_time):
        """Loads JSONL data and filters it based on the selected date."""
        data = []
        flag = False
        date = datetime.fromtimestamp(selected_time).date()
        try:
            with open( dir +"/"+str(date) + self.file_path, "r", encoding="utf-8") as file:
                for line in file:
                    try:
                        entry = json.loads(line.strip())  # Parse JSON line
                        data.append(entry)
                    except json.JSONDecodeError as e:
                        flag = True
                        print(f"Invalid JSON: {line.strip()}")  # Debugging
                        print(f"Error: {e}")
        except:
            pass
        if flag:
            with open(dir +"/"+ str(date)+self.file_path, "w", encoding="utf-8") as file:
                for d in data:
                    json.dump(d, file)
                    file.write("\n")
        try:
            data = sorted(data, key=lambda x: x["timestamp"],reverse= True)
        except:
            pass
        return data

    def refresh_table(self):
        """Clears and refreshes table data based on filtered JSONL data."""
        self.root.after(30000, self.refresh_table)  # Refresh every 10 seconds
        for item in self.tree.get_children():
            self.tree.delete(item)
        selected_date = self.date_entry.get_date()
        selected_datetime = datetime.combine(selected_date, datetime.min.time())  # Convert to full datetime
        selected_timestamp = int(selected_datetime.timestamp())  
        json_data = self.load_data(selected_timestamp)

        if not json_data:
            return

        for entry in json_data:
            try:
                self.tree.insert("", "end", values=(
                    datetime.fromtimestamp(entry["timestamp"]).strftime('%d-%m-%y %H:%M:%S'),
                    entry["ph"], entry["temp"], entry["cod"],
                    entry["ss"], entry["waterflow"]
                ))
            except KeyError as e:
                print(f"Missing key in JSON entry: {e}")

    def auto_refresh(self,event):
        self.refresh_table()

    # GUI Setup
    def on_touch_scroll(self,event):
        now = event.y
        trigger = now - self.last
        self.last = now
        if trigger > 0:  # Swiping down (positive y-axis)
            self.tree.yview_scroll(-1, "units")
        elif trigger < 0:  # Swiping up (negative y-axis)
            self.tree.yview_scroll(1, "units")


class Graph():
    def __init__(self,root):
        start = time.time()
        self.window = root
        self.window.title('Plotting in Tkinter') 
        # Your window setup ...
        screen_width = self.window.winfo_screenwidth()
        screen_height = self.window.winfo_screenheight()
        
        # dimensions of the main window 
        self.window.geometry(f"{screen_width}x{screen_height}")

        self.header_frame = tk.Frame(self.window, bg="#f0f0f0")
        self.header_frame.grid(row=0, column=0, sticky="nsew", pady=10)

        # Month Selection
        self.month_var = tk.StringVar()
        self.months = [datetime(1900, m, 1).strftime('%B') for m in range(1, 13)]
        self.month_combo = ttk.Combobox(self.header_frame, textvariable=self.month_var, values=self.months, state="readonly")
        
        current_month = datetime.today().strftime('%B')
        self.month_var.set(current_month)  # Set StringVar directly
        self.month_combo.set(current_month)  # Set ComboBox default
        self.month_combo.pack(side="left", padx=5, pady=5)
        self.month_combo.bind("<<ComboboxSelected>>", self.draw_graph)

        # Year Selection
        self.year_var = tk.StringVar()
        years = [str(y) for y in range(2010, 2050)]
        self.year_combo = ttk.Combobox(self.header_frame, textvariable=self.year_var, values=years, state="readonly")
        
        current_year = str(datetime.today().year)
        self.year_var.set(current_year)  # Set StringVar directly
        self.year_combo.set(current_year)  # Set ComboBox default
        self.year_combo.pack(side="left", padx=5, pady=5)
        self.year_combo.bind("<<ComboboxSelected>>", self.draw_graph)

        self.graph_frame= tk.Frame(self.window,bg="#f0f0f0")
        self.graph_frame.grid(row = 1, column= 0, sticky="nsew")

        # Create the figure and plot
        self.fig = Figure(figsize=(screen_width / 80, screen_height / 80), dpi=80)
        self.plot = self.fig.add_subplot()

        # Draw the canvas
        self.canvas = FigureCanvasTkAgg(self.fig, master=self.graph_frame)
        # Display the canvas in the Tkinter window
        self.canvas.get_tk_widget().pack()
        self.draw_graph()

    def draw_graph(self,even = None): 
        self.plot.clear()
        self.lines = []
        # Load the data
        selected_month = self.month_var.get()
        month_int = self.months.index(selected_month) + 1 
        
        selected_year = int(self.year_var.get())

        data = self.load_data(selected_year, month_int)
        for entry in data :
            entry['timestamp'] = datetime.strptime(entry['timestamp'], "%Y-%m-%d")

        phs = [entry["ph"] for entry in data]
        temps = [entry["temp"] for entry in data]
        cods = [entry["cod"] for entry in data]
        sss = [entry["ss"] for entry in data]
        waterflows = [entry["waterflow"] for entry in data]
        timestamps = [entry["timestamp"] for entry in data]

        # Plot the data
        self.plot_data(phs, timestamps, color="pink", label="PH")
        self.plot_data(temps, timestamps, color="blue", label="Temperature")
        self.plot_data(cods, timestamps, color="green", label="COD")
        self.plot_data(sss, timestamps, color="red", label="SS")
        self.plot_data(waterflows, timestamps, color="yellow", label="Waterflow")

        # Adjust the x-axis and labels
        start_date = data[0]["timestamp"]
        end_date = data[-1]["timestamp"]
        for entry in data:
            if entry["ph"] is not None or entry["temp"] is not None or entry["cod"] is not None or entry["ss"] is not None or entry["waterflow"] is not None:
                start= entry["timestamp"]
                if start > start_date:
                    start_date = start - timedelta(days=1)
                break
        for entry in reversed(data):
            if entry["ph"] is not None or entry["temp"] is not None or entry["cod"] is not None or entry["ss"] is not None or entry["waterflow"] is not None:
                end = entry["timestamp"]
                if end < end_date:
                    end_date = end + timedelta(days=1)
                break


        self.plot.set_xlim(start_date, end_date)
        self.plot.xaxis.set_major_formatter(mdates.DateFormatter("%Y-%m-%d"))
        self.plot.xaxis.set_major_locator(mdates.DayLocator(interval=1))
        self.fig.autofmt_xdate()

        # Add labels and title
        self.plot.set_xlabel('Date')
        self.plot.set_ylabel('Sensor Values')
        self.plot.set_title('Water Quality Sensor Data')
        self.plot.legend(handles= self.lines)
        self.plot.grid(True)
        
        self.canvas.draw()

        # Apply mplcursors to show date and data on hover
        mplcursors.cursor(self.plot.collections, hover=True).connect(
            "add", lambda sel: sel.annotation.set_text(
                f"Date: {mdates.num2date(sel.target[0]):%Y-%m-%d}\n{sel.artist.get_label()}: {sel.target[1]:.2f}"
                
            )
        )

    def findfile(self,year, month):
        # Get the number of days in the current month
        _, num_days = calendar.monthrange(year, month)

        # Generate the formatted date for each day in the month
        formatted_date = []
        for day in range(1, num_days + 1):
            day_date = datetime(year, month, day)
            formatted_date.append(day_date.strftime("%Y-%m-%d"))
        return formatted_date
    
    def load_data(self, year, month):

        date = self.findfile(year, month)


        if month < 10:
            space = "-0"
        else:
            space = "-"
        file_path =dir+"/"+str(year)+space+str(month)+".jsonl"
        data = []
        try:
            with open(file_path, "r") as file:
                for line in file:
                    try:
                        entry = json.loads(line.strip())  # Parse JSON line
                        data.append(entry)
                    except json.JSONDecodeError as e:
                        flag = True
                        print(f"Invalid JSON: {line.strip()}")  # Debugging
                        print(f"Error: {e}")
        except:
            pass
        final_data = []
        i =0
        for d in date:
            if d == str(datetime.today().date()):
                tmp = []
                with open(dir+ "/"+d+"data.jsonl", 'r') as file:
                    for line in file:
                        try:
                            entry = json.loads(line.strip())  # Parse JSON line
                            tmp.append(entry)
                        except json.JSONDecodeError as e:
                            flag = True
                            print(f"Invalid JSON: {line.strip()}")  # Debugging
                            print(f"Error: {e}")
                len_ph = len_temp = len_cod = len_ss = len_waterflow = len(tmp)
                for entry in tmp:
                    if entry["ph"] == None:
                        len_ph -= 1
                    if entry["temp"] == None:
                        len_temp -= 1
                    if entry["cod"] == None:
                        len_cod -= 1
                    if entry["ss"] == None:
                        len_ss -= 1
                    if entry["waterflow"] == None:
                        len_waterflow -= 1
                filterData = {
                    "ph": round(sum([entry["ph"] for entry in tmp if entry["ph"] != None])/len_ph, 2) if len_ph != 0 else None,
                    "temp": round(sum([entry["temp"] for entry in tmp if entry["temp"] != None])/len_temp, 2) if len_temp != 0 else None,
                    "cod": round(sum([entry["cod"] for entry in tmp if entry["cod"] != None])/len_cod, 2) if len_cod != 0 else None,
                    "ss": round(sum([entry["ss"] for entry in tmp if entry["ss"] != None])/len_ss, 2) if len_ss != 0 else None,
                    "waterflow": round(sum([entry["waterflow"] for entry in tmp if entry["waterflow"] != None])/len_waterflow, 2) if len_waterflow != 0 else None,
                    "timestamp": d
                                }
                final_data.append(filterData)
                
            elif i < len(data) and d in data[i]['timestamp'] :
                tmp = {
                    "ph": data[i]['ph'],
                    "temp": data[i]['temp'],
                    "cod": data[i]['cod'],
                    "ss": data[i]['ss'],
                    "waterflow": data[i]['waterflow'],
                    "timestamp": d
                }
                final_data.append(tmp)
                i += 1
            else:
                tmp = {
                    "ph": None,
                    "temp": None,
                    "cod": None,
                    "ss": None,
                    "waterflow": None,
                    "timestamp": d
                }
                final_data.append(tmp)
        return final_data


# Modify plot_data function to return scatter plot objects
    def plot_data(self,datas, timestamps, color=None, label=None):
        self.plot.scatter(timestamps,datas,c= color,label = label)
        self.plot.plot(timestamps,datas, '-', color=color, label=label)
        line,= self.plot.plot([],[],'o-', label = label)
        self.lines.append(line)



class DataDisplayApp:
    def __init__(self, root ):
        print("screen started")
        self.root = root
        self.root.title("Environmental Data Display")
        root.attributes('-fullscreen', True) 
        
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
        self.graph_button = self.create_button("Graph", cmd= self.update_graph)
        self.settings_button = self.create_button("Settings")
        self.about_button = self.create_button("About Me")

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

        try:
            with open(dir + "/date.json", "r") as file:
                file_date = json.load(file)
                saved_date = datetime.strptime(file_date["date"], "%Y-%m-%d").date()

            self.lastdate = saved_date 
        except :
            self.lastdate = datetime.today().date()

        self.fush  = False
        
        self.reader = RS485()
        self.ph = self.tss = self.cod = self.toc = self.temp = self.waterflow = None
        self.mqtt_client = MQTTClient()
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
        button = tk.Button(self.button_frame, text=text, font=("Arial", 18, "bold"), bg="#4CAF50", fg="white", width=4, height=2,bd = 5,activeforeground= "white",activebackground= "#4CAF50",command= cmd)
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

                    data = {
                        "ph": self.ph,
                        "temp": self.temp,
                        "cod": self.cod,
                        "ss": self.tss,
                        "toc":self.toc,
                        "waterflow" : self.waterflow,
                        "timestamp" : round(time.time())
                    }
                    
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

                    # Extract only the date (without time)
                    
                    date_time = datetime.fromtimestamp(data["timestamp"])
                    date = date_time.date()

                    file_date = {
                        "date": str(date)
                    }
                    
                    
                    if self.lastdate != date:
                        data = []
                        filterData = {}
                        with open(dir + "/"+ str(self.lastdate)+ "data.jsonl", "r") as file :
                            for line in file:
                                try:
                                    entry = json.loads(line.strip())  # Parse JSON line
                                    data.append(entry)
                                except json.JSONDecodeError as e:
                                    flag = True
                                    print(f"Invalid JSON: {line.strip()}")  # Debugging
                                    print(f"Error: {e}")
                        len_ph = len_temp = len_cod = len_ss = len_waterflow = len(data)
                        for entry in data:
                            if entry["ph"] == None:
                                len_ph -= 1
                            if entry["temp"] == None:
                                len_temp -= 1
                            if entry["cod"] == None:
                                len_cod -= 1
                            if entry["ss"] == None:
                                len_ss -= 1
                            if entry["waterflow"] == None:
                                len_waterflow -= 1
                        filterData = {"ph": round(sum([entry["ph"] for entry in data if entry["ph"] != None])/len_ph, 2) if len_ph != 0 else None,
                                        "temp": round(sum([entry["temp"] for entry in data if entry["temp"] != None])/len_temp, 2) if len_temp != 0 else None,
                                        "cod": round(sum([entry["cod"] for entry in data if entry["cod"] != None])/len_cod, 2) if len_cod != 0 else None,
                                        "ss": round(sum([entry["ss"] for entry in data if entry["ss"] != None])/len_ss, 2) if len_ss != 0 else None,
                                        "waterflow": round(sum([entry["waterflow"] for entry in data if entry["waterflow"] != None])/len_waterflow, 2) if len_waterflow != 0 else None,
                                        "timestamp": str(datetime.combine(datetime.strptime(str(self.lastdate),"%Y-%m-%d"),datetime.min.time()))}
                        with open( dir + "/"+self.lastdate.strftime("%Y-%m")+".jsonl" , 'a') as file:
                            json.dump(filterData,file)
                            file.write("\n")
                        self.lastdate = date
                        with open(dir +"/date.json", "w" ) as file:
                            json.dump(file_date, file)

                    try:
                        with open(dir + "/"+str(date)+"data.jsonl", "a") as file:
                            json.dump(data, file)
                            file.write("\n")
                    except FileNotFoundError:
                        with open(dir + "/" + str(date)+"data.jsonl", "w") as file:
                            json.dump(data, file)
                            file.write("\n")
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
            self.ph = round(random.uniform(4.50, 9.50),2)
            self.tss = round(random.uniform(0, 50),2)
            self.cod = round(random.uniform(25, 68),2)
            self.toc = round(random.uniform(4, 25),2)
            self.temp = round(random.uniform(20, 50),2)
            self.waterflow = None
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
        table = Table(new_screen)

    def update_graph(self):
        new_screen = tk.Toplevel(self.root)
        graph = Graph(new_screen)
if __name__ == "__main__":
    try:
        with open("/tmp/isRun.txt" , "r") as file:
            pass
        root = tk.Tk()
        app = DataDisplayApp(root)
        root.mainloop()
    except  Exception as e:
        print(e)
        with open("/tmp/isRun.txt", "w") as file :
            file.write("1")
        pass
EOF