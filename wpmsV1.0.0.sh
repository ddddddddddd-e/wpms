#!/bin/bash

# Get the directory of the script
script_dir="/home/kickpi/Desktop/wpms/"

# Set the environment variable for Python to access
export FILE_PATH="$script_dir"



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
from tkinter import messagebox  

import matplotlib.dates as mdates

from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from matplotlib.figure import Figure 

import calendar
import mplcursors
import subprocess

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
                data = {"server": "iot.moe.gov.kh","port": 8883,"username":"iot","password":"&j?/yO^{c[?+ub","userId": get_mac_addresses(),"topic": "test","interval": 30,"security":True}
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
    def set_user_pass(self, username : str, password :str):
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
    def publish(self,ph: float, temp: float, cod :float, ss :float, waterflow: float):
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
        json_payload = json.dumps(payload)
        self.publish_dict(json_payload)
    
    def publish_dict(self,payload ):
        
        if self.client.is_connected():  # Check if connected
            self.client.publish(self.topic_send, str(payload))
        else:
            global dir
            with open(dir + "/buffer_data.jsonl","a") as file:
                json.dump(json.loads(payload),file)
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
        self.interval = 30000
        
        column_width = screen_width // 6

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
            self.tree.column(col,width= column_width, anchor="center")

        # Attach the Scrollbar to the Treeview
        self.tree_scroll.config(command=self.tree.yview)
        self.tree.pack(fill="both", expand=True)
        self.last = 500
        
        self.tree.bind("<ButtonPress-1>", lambda e: setattr(self, "mouse_held", True) or setattr(self, "last", e.y))
        self.tree.bind("<ButtonRelease-1>", lambda e: setattr(self, "mouse_held", False))
        self.tree.bind("<B1-Motion>", self.on_touch_scroll_hold)
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
                        entry['ph']
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
        self.root.after(self.interval, self.refresh_table)  # Refresh every 10 seconds
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
    def on_touch_scroll_hold(self, event):
        if self.tree.selection():  # Only scroll if something is selected
            scroll_units = -(event.y - self.last) // 10  # Or some other scale factor
            if scroll_units != 0:
                self.tree.yview_scroll(int(scroll_units), "units")
                self.last = event.y


class Graph():
    def __init__(self,root :tk.Tk):
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
        self.plot_data(phs, timestamps, color="#00BFFF", label="PH")
        self.plot_data(temps, timestamps, color="#FFBF00", label="Temperature")
        self.plot_data(cods, timestamps, color="#FF4500", label="COD")
        self.plot_data(sss, timestamps, color="#006400", label="SS")
        self.plot_data(waterflows, timestamps, color="#8A2BE2", label="Waterflow")

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
        self.fig.legend(handles= self.lines,loc = "upper left")
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
                try:
                    with open(dir+ "/"+d+"data.jsonl", 'r') as file:
                        for line in file:
                            try:
                                entry = json.loads(line.strip())  # Parse JSON line
                                try:
                                    entry['ph']
                                    tmp.append(entry)
                                except Exception as e:
                                    flag = True
                            except json.JSONDecodeError as e:
                                flag = True
                                print(f"Invalid JSON: {line.strip()}")  # Debugging
                                print(f"Error: {e}")
                except:
                    pass
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
        line,= self.plot.plot([],[],'o-', label = label,color= color)
        self.lines.append(line)

class Config:
    def __init__(self, master: tk.Tk):
        self.root = master
        self.root.title("Login to MQTT Config")
        self.screen_width = self.root.winfo_screenwidth()
        self.screen_height = self.root.winfo_screenheight()

        # Set the window to cover the full screen size
        


        # Create login UI
    def start(self):
        self.root.geometry(f"{self.screen_width}x{self.screen_height}")
        tk.Button(self.root, text="Login",font=("Arial", 25), command=self.build_login_ui).pack(pady=10)
        

    def build_login_ui(self):
        if hasattr(self, 'master') and self.master.winfo_exists():
            self.master.lift()
            return
        if hasattr(self, 'config_screen') and self.config_screen.winfo_exists():
            self.config_screen.lift()
            return
        self.master = tk.Toplevel(self.root)
        self.master.geometry(f"{self.screen_width}x{self.screen_height}")
        self.master.title("Login")
        self.master.configure(bg="#dcdcdc")

        self.center_frame = tk.Frame(self.master, bg="white", bd=2, relief=tk.RIDGE, padx=30, pady=30)
        self.center_frame.place(relx=0.5, rely=0.5, anchor=tk.CENTER)

        tk.Label(
            self.center_frame, text="THIS IS FOR TECHNICIAN ONLY !!!",
            font=("Arial", 20, "bold"), fg="black", bg="white"
        ).grid(row=0, column=0, columnspan=2, pady=(0, 20))

        # Username row
        tk.Label(self.center_frame, text="Username:", font=("Arial", 16), bg="white").grid(row=1, column=0, sticky="e", pady=5, padx=(0,10))
        self.username_entry = tk.Entry(self.center_frame, font=("Arial", 16), width=25)
        self.username_entry.grid(row=1, column=1, pady=5)

        # Password row
        tk.Label(self.center_frame, text="Password:", font=("Arial", 16), bg="white").grid(row=2, column=0, sticky="e", pady=5, padx=(0,10))
        self.password_entry = tk.Entry(self.center_frame, font=("Arial", 16), width=25, show="*")
        self.password_entry.grid(row=2, column=1, pady=5)

        # Login button
        tk.Button(
            self.center_frame, text="Login", font=("Arial", 16),
            bg="#4CAF50", fg="white", width=20, command=self.do_login
        ).grid(row=3, column=0, columnspan=2, pady=20)

        self.master.bind('<Return>', self.do_login)

    def do_login(self, event=None):
        username = self.username_entry.get()
        password = self.password_entry.get()
        self.master.destroy()

        try:
            with open(f"{dir}/login.json", "r") as file:
                data = json.load(file)
            if username == data["username"] and password == data["password"]:
                
                self.show_mqtt_form()
            else:
                messagebox.showerror("Login Failed", "Incorrect username or password.")
            
        except Exception as e:
            messagebox.showerror("Error", f"Could not read login.json:\n{e}")
            with open(f"{dir}/login.json", "w") as file:
                data = {"username": "Admin", "password": "password"}
                json.dump(data, file, indent=4)

    def show_mqtt_form(self):
        self.config_screen = tk.Toplevel(self.root)
        self.config_screen.geometry(f"{self.screen_width}x{self.screen_height}")
        self.config_screen.title("MQTT Config")
        self.config_screen.configure(bg="#dcdcdc")

        # Center bordered frame
        self.form_frame = tk.Frame(self.config_screen, bg="white", bd=2, relief=tk.RIDGE, padx=30, pady=30)
        self.form_frame.place(relx=0.5, rely=0.5, anchor=tk.CENTER)
        self.entries = {}
        def create_field(label, key, show=None, default=""):
            row = len(self.entries)
            label_widget = tk.Label(
                self.form_frame, text=label, width=12, anchor='e',
                font=("Arial", 20), bg="white"
            )
            label_widget.grid(row=row, column=0, pady=5, padx=(0, 10), sticky='e')

            entry = tk.Entry(self.form_frame, width=30, font=("Arial", 20), show=show)
            entry.insert(0, default)
            entry.grid(row=row, column=1, pady=5, padx=(0, 5))
            self.entries[key] = entry

            if show:
                def toggle_show():
                    if entry.cget('show') == '':
                        entry.config(show=show)
                        toggle_btn.config(text='Show')
                    else:
                        entry.config(show='')
                        toggle_btn.config(text='Hide')

                toggle_btn = tk.Button(
                    self.form_frame, text='Show', font=("Arial", 12),
                    command=toggle_show, bg="#e0e0e0"
                )
                toggle_btn.grid(row=row, column=2, padx=(5, 0))

        try:
            with open(f"{dir}/config.json", "r") as file:
                data = json.load(file)
        except Exception as e:
            print(e)
        if data:
            create_field("Server:", "server",default=data["server"])
            create_field("Port:","port",default= str(data["port"]))
            create_field("Topic:", "topic",default=data["topic"])
            create_field("Username:", "username",default=data["username"])
            create_field("Password:", "password", show="*",default=data["password"])
            create_field("UserID:", "userId",default=data["userId"])
            create_field("Interval:", "interval",default= str(data["interval"]))
        else:
            create_field("Server:", "server",show="*")
            create_field("Port:","port",show="*")
            create_field("Topic:", "topic",show="*")
            create_field("Username:", "username",show="*")
            create_field("Password:", "password", show="*")
            create_field("UserID:", "userId",show="*")
            create_field("Interval:", "interval",show="*")

        submit_btn = tk.Button(
            self.form_frame, text="Submit", font=("Arial", 20),
            bg="#4CAF50", fg="white", padx=10, pady=2,
            command=self.submit_mqtt
        )
        submit_btn.grid(row=len(self.entries), column=0, columnspan=3, pady=5, padx=5)
        # Bind Enter key to submit
        self.config_screen.bind('<Return>', lambda event: self.submit_mqtt())

    def submit_mqtt(self):
        config = {k: e.get() for k, e in self.entries.items()}
        print(config)
        config["security"] = True
        self.config_screen.destroy()
        try:
            config["port"] = int(config["port"])
            config["interval"] = int(config["interval"])
            with open(f"{dir}/config.json", "w") as file:
                json.dump(config, file, indent=4)
            messagebox.showinfo("Success", "Configuration saved successfully.\n please restart to apply the configuration.")
            password = "kickpi"
            command = "echo {0} | sudo -S reboot".format(password)

            try:
                subprocess.run(command, shell=True)
            except Exception as e:
                print(f"Failed to reboot: {e}")

        except Exception as e:
            messagebox.showerror("Error", f"Could not save configuration:\n{e}")
            print(e)
        

class AboutUsWindow:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.screen_width = self.root.winfo_screenwidth()
        self.screen_height = self.root.winfo_screenheight()

    def start(self):
        about_win = tk.Toplevel(self.root)
        about_win.title("About Us")
        about_win.geometry(f"{self.screen_width}x{self.screen_height}")
        about_win.configure(bg="#f0f0f0")

        frame = tk.Frame(about_win, bg="white", bd=2, relief=tk.RIDGE, padx=20, pady=20)
        frame.pack(expand=True, fill="both", padx=40, pady=40)

        title = tk.Label(frame, text="About Us", font=("Arial", 24, "bold"), bg="white")
        title.pack(pady=(0, 20))

        # Text widget in a frame with a scrollbar
        text_frame = tk.Frame(frame, bg="white")
        text_frame.pack(expand=True, fill="both")

        text_widget = tk.Text(text_frame, wrap="word", font=("Arial", 14), bg="white", relief=tk.FLAT)
        text_widget.pack(side="left", fill="both", expand=True)

        scrollbar = ttk.Scrollbar(text_frame, command=text_widget.yview)
        scrollbar.pack(side="right", fill="y")
        text_widget.config(yscrollcommand=scrollbar.set)

        about_text = (
            "We are a passionate team dedicated to advancing environmental monitoring through smart technology.\n\n"
            "Our current project, developed under the support of the Ministry of Environment (MoE), focuses on "
            "creating an IoT-based system for real-time water quality monitoring.\n\n"
            "Our custom-built device is designed to detect and collect critical water parameters including:\n"
            "• COD (Chemical Oxygen Demand)\n"
            "• pH levels\n"
            "• TSS (Total Suspended Solids)\n"
            "• Temperature\n"
            "• Water Flow Rate\n\n"
            "This system provides accurate, continuous data collection to help ensure water safety and sustainability. "
            "We aim to empower researchers, institutions, and environmental agencies with reliable insights for "
            "decision-making and action.\n\n"
            "By combining sensor technology, data processing, and IoT connectivity, we are committed to making "
            "environmental monitoring smarter, faster, and more efficient."
        )
        text_widget.insert("1.0", about_text)
        text_widget.config(state="disabled")

class DataDisplayApp:
    def __init__(self, root :tk.Tk ):
        print("screen started")
        self.root = root
        self.root.title("Environmental Data Display")
        root.attributes('-fullscreen', True) 
        
        self.root.config(bg="#f0f0f0")
        self.root.grid_rowconfigure(0, weight=1)  # Allow vertical expansion
        self.root.grid_rowconfigure(1, weight=5)  # Allow vertical expansion
        self.root.grid_rowconfigure(2, weight=1)  # Allow vertical expansion
        self.root.grid_columnconfigure(0, weight=1)  # Allow vertical expansion

        self.setting = Config(self.root)
        self.about = AboutUsWindow(self.root)

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
        self.settings_button = self.create_button("Settings",cmd = self.setting.build_login_ui)
        self.about_button = self.create_button("About Me",self.about.start)

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

    def create_text_box(self, initial_text : str):
        frame = tk.Frame(self.data_frame, bg="#3f9fd8", bd=3, relief="solid")
        text_box = tk.Text(frame, font=("Arial", 20), bg="white", fg="black", wrap=tk.WORD, bd=5)

        text_box.insert(tk.END, "\n" +initial_text)
        text_box.config(state=tk.DISABLED)
        text_box.pack(fill=tk.BOTH, expand=True, padx=5, pady=5,anchor= "center",side = "right")       
        frame.pack_propagate(False)
        return frame
    def create_button(self, text : str,cmd = None ):
        button = tk.Button(self.button_frame, text=text, font=("Arial", 18, "bold"), bg="#4CAF50", fg="white", width=4, height=2,bd = 5,activeforeground= "white",activebackground= "#4CAF50",command= cmd)
        return button

    def create_led(self,text : str):
        label = tk.Label(self.status_frame, text=f" {text}:", font=("Arial", 11), bg="#f0f0f0")
        label.pack(side="left", padx=1)

        led = tk.Canvas(self.status_frame, width=20, height=20, bg="#f0f0f0", highlightthickness=0)
        led.pack(side="left", padx=5)
        led.create_oval(2, 2, 18, 18, fill="red", tags="led")  # Default: Red
        return led
    def exit(self):
        self.root.destroy()
    
    # edit text 
    def update_text_box(self, text_box : tk.Text, new_data :str):
        """Update the content of a text box."""
        text_box.config(state=tk.NORMAL)  # Enable editing
        text_box.delete(1.0, tk.END)  # Clear the existing content
        text_box.insert(tk.END, "\n"+new_data)  # Insert the new data
        text_box.config(state=tk.DISABLED)  # Make it read-only again
    
    def update_led(self, canvas : FigureCanvasTkAgg, color : str):
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
                    
                    try:
                        with open(dir + "/"+str(date)+"data.jsonl", "a") as file:
                            json.dump(data, file)
                            file.write("\n")
                    except FileNotFoundError:
                        with open(dir + "/" + str(date)+"data.jsonl", "w") as file:
                            json.dump(data, file)
                            file.write("\n")
                    
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
        # Prevent multiple table windows
        if hasattr(self, 'table_window') and self.table_window.winfo_exists():
            self.table_window.lift()
            return

        self.table_window = tk.Toplevel(self.root)
        # Replace with your actual Table class
        Table(self.table_window)

        def on_close():
            self.table_window.destroy()

        self.table_window.protocol("WM_DELETE_WINDOW", on_close)

    def update_graph(self):
        if hasattr(self, 'graph_window') and self.graph_window.winfo_exists():
            self.graph_window.lift()  # Bring to front if it's already open
            return

        self.graph_window = tk.Toplevel(self.root)

        Graph(self.graph_window)

        def on_close():
            self.graph_window.destroy()

        self.graph_window.protocol("WM_DELETE_WINDOW", on_close)

if __name__ == "__main__":
    
    try:
        with open("/tmp/isRun.txt" , "r") as file:
            pass
        os.remove("/tmp/isRun.txt")
    except  Exception as e:
        print(e)
        with open("/tmp/isRun.txt", "w") as file :
            file.write("1")
        root = tk.Tk()
        app = DataDisplayApp(root)
        root.mainloop()
    finally:
        os.remove("/tmp/isRun.txt")
    

EOF