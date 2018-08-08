## Hardware and Software Stack

The Samasy interface can easily run on commodity hardware with internet access. The suggested hardware requirements are a 1Ghz processor, 512MB of RAM, and 1GB of storage space. Actual requirements depend primarily on the number of samples and concurrent users, but are likely much lower, and a vast majority of implementations will require no special consideration. Samasy has been successfully tested with a project consisting of more than 700 plates, 15,000 transfers, and 80 batches. 

For optimal performance the following software stack is recommended:

* Ubuntu&nbsp;&nbsp;&nbsp;&nbsp;http://www.ubuntu.com/
* Nginx&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;http://nginx.org/  
* Sqlite3&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;http://www.sqlite.org/  
* Ruby&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;https://www.ruby-lang.org/en/  
* Sinatra&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;http://www.sinatrarb.com/  

This software was chosen based on its usage license (free), ease of use, and general community support. Of these, only Ruby and Sinatra are required. Ubuntu as an operating system is recommended as the installation of software packages is described using Ubuntu’s apt-get command. The use of nginx as a server as opposed to Ruby’s rack is optional, but reflects a choice between optimizing ease-of-use (rack) and increased security, functionality, and performance (nginx). As for choice of database, the software framework is agnostic-- PostgreSQL or MySQL are equally acceptable over Sqlite3, but require several additional steps to configure. Simple configuration was prefered in all cases to get users up and running as quickly as possible. 


## The Samasy Application and Components

Samasy is implemented in the Ruby programming language using a web application framework called Sinatra. Web application frameworks are responsible for taking requests from a web browser, deciding what actions to perform (often involves processing information from a database), and rendering responses back to the browser (typically a web page). Conceptually, frameworks often follow a MCV (Model Controller View) paradigm. The model specifies how the application’s data is structured and stored (eg. database) and the view how it is displayed (eg. a web page or data structure). The controller directs this process and logical flow, intercepting web browser requests and serving back appropriate responses. 



In addition to serving data to the user’s browser, Sinatra also serves code in the form of javascript, which allows the user to interact with the page dynamically. Javascript is typically served with the relevant view, though sometimes it is sent as a separate response if the code is used across several rendered views. 

### Initialization Code

Before the Samasy is started, the web framework loads all required modules (gems), configures database settings, initializes key-value stores, and defines miscellaneous functions that handle tasks like verifying and authenticating users. This code is found in the config.ru file. Finally, the main controller code in main.rb and database processing functions in db.rb are instantiated. Ruby gems are installed using the bundle command as described in the documentation. This command opens the Gemfile and ensures that all the gems listed have been installed. The default web server, rack, is started using the rackup command, which will start a server responding to http://localhost:9292 by default.

### The Controller

The heart of the Samasy application is the controller code, which is found in main.rb. This file specifies which URLs (or routes) that the web framework responds to and defines a set of interactions with sample information found in the database. The file is divided into several types of routes:
*	Static files  
*	Template renderers  
*	REST/JSON routes  
*	Status and DB triggers  
*	File handlers (upload/download)  
*	User Authentication  

### The Database

Samasy controls the database backend using Ruby’s DataMapper, and code is found in the db.rb file. In this file, several applications objects are defined, including:
*	User  
*	Sample and Well  
* Plate  
*	Batch and Mapping  
*	Coding (if a data dictionary is used)  

There are also additional functions that provide database support, including type-guessing, sample validation, and data import. 
