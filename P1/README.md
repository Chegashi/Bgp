README for Part 1: GNS3 Configuration with Docker
Overview
In this project, you will configure GNS3 with Docker to simulate a network environment. This is the first step in the "Bgp At Doors of Autonomous Systems is Simple (BADASS)" project, laying the groundwork for exploring VXLAN and BGP with EVPN.

Tools
GNS3: Network simulator for building and testing network configurations.
Docker: Platform for developing and running containerized applications.
Instructions
Setup GNS3 and Docker on your virtual machine.
Create Two Docker Images:
One with a basic system like Alpine Linux, including BusyBox.
Another with a routing software (Zebra or Quagga), configured with BGPD, OSPFD, and IS-IS.
Integrate Images in GNS3: Ensure both Docker containers function correctly within GNS3.
Save Configurations: Store all project files in a folder named P1 at the root of your repository.
Export Project: Compress the project, including base images, into a ZIP file and include it in your repository.
