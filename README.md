## How to scale out with AWS

I couldn't get any big clusters to run the other day for a variety of reasons, so I took some time to figure out how to do it this weekend!

The first problem was that a lot of the instance types needed a VPC(Virtual Private Cloud) to start, and for some reason the script we had wasn't booting on the default VPC.

Here is a wonderful website (https://www.ec2instances.info/) that updates from amazon and displays information about all of the instance types, including older instances like m3: (enable the EMR pricing column to check EMR prices, and keep in mind that the EMR price is in addition to the instance cost). You can check to see if instances are VPC-only as well.

A VPC is basically a private virtual network in your AWS account; before VPC EC2 used EC2-Classic, where you would share a network with others.
If an instance is VPC only, you need to provide a subnet (a range of IP addresses in your VPC) for your default VPC (which AWS should have already created for you) when you launch your cluster.
To find your subnet, go to the AWS console, make sure you're in the correct region, type VPC into the AWS services box, and click on subnets. When you use the AWS command line interface, you need to add the subnetid to the --ec2-attributes argument, like below. (or change just mine!)


<img src = "img/VPC.jpg" width=800>

The other changes I made to the launch clusters script are updating the emr version to 5.16.0 (which loads spark 2.3.1 by default), changing the instance type, adding a log destination in the s3 bucket so you can debug failed clusters, and adding Ganglia. Ganglia allows you to monitor your cluster in much more detail than the EMR page, similar to a task manager or top / htop.

#### launch_cluster.sh
```
#!/bin/bash

# Takes three arguments:
#   bucket name - one that has already been created
#   name of key file - without .pem extension
#   number of slave instances
#      ex. bash launch_cluster.sh mybucket mypem 2

# This script assumes that the file bootstrap-emr.sh is
#   in your current directory.

# Requires the awscli to be set up, need to have correct default region configured
# Run `aws configure` to set this up

# require for first time cluster creators.
# you can comment this out if you are sure
# that the default emr roles already exist
aws emr create-default-roles

aws s3 cp emr-config.sh s3://$1/scripts/emr-config.sh

aws emr create-cluster \
    --enable-debugging \
    --log-uri s3://$1/new_logm4 \
    --name PySparkCluster \
    --release-label emr-5.16.0 \
    --applications Name=Spark Name=Ganglia \
    --ec2-attributes KeyName=$2,SubnetIds=subnet-0dc89157 \
    --use-default-roles \
    --instance-groups \
      InstanceGroupType=MASTER,InstanceCount=1,InstanceType=c3.2xlarge \
      InstanceGroupType=CORE,InstanceCount=$3,InstanceType=mc3.2xlarge \
    --bootstrap-actions Path=s3://$1/scripts/emr-config.sh
```

Another issue I had was exceeding my EC2 instance limits, even though I only had a couple workers running. Well, the number of EC2 instances you can have running at one time is determined by the instance type. To view a comprehensive list of instance limits, go to the AWS console, make you're in the right region, search for EC2 and then click limits on the top left side. You can see that many instances have a current limit of 0 or 1. If you need more, you will need to request a limit increase.

This page coupled with the ec2instances.info will help you decide on a good cluster. For example if you have a limit of 5 c3.2xlarge, you can use one for your master and four as workers for 40 vCores and 75GiB of memory.

Sometimes I also got a boostrap timeout, which was caused by several reasons; one being that the bootstrap script was trying to install on /mnt1, which existed on older EC2 instances that had a drive attached to them, whereas newer instances often have EBS only storage and no extra mount point. I ended up downloading a new bootstrap script and modifying it a bit; it looks like this:

#### bootstrap-emr.sh
```

WS EMR 5.4.0 bootstrap script for installing/configuring Anaconda, additional
# Python packages, Tensorflow w/Keras, and Theano
# Modified from David Ziganto (dziganto.github.io)
# ----------------------------------------------------------------------
#  move /usr/local to /mnt/usr-moved/local; else run out of space on /
# ----------------------------------------------------------------------
sudo mkdir /mnt/usr-moved
sudo mv /usr/local /mnt/usr-moved/
sudo ln -s /mnt/usr-moved/local /usr/
sudo mv /usr/share /mnt/usr-moved/
sudo ln -s /mnt/usr-moved/share /usr/

# ----------------------------------------------------------------------
#              Install Anaconda (Python 3) & Set To Default
# ----------------------------------------------------------------------
wget https://repo.continuum.io/archive/Anaconda3-5.2.0-Linux-x86_64.sh -O ~/anaconda.sh
bash ~/anaconda.sh -b -p $HOME/anaconda
echo -e '\nexport PATH=$HOME/anaconda/bin:$PATH' >> $HOME/.bashrc && source $HOME/.bashrc

# ----------------------------------------------------------------------
#                    Install Additional Packages
# ----------------------------------------------------------------------
conda install -y psycopg2 gensim
pip install textblob selenium

# ----------------------------------------------------------------------
#         Install Tensorflow (CPU only and installs Keras )
# ----------------------------------------------------------------------
# conda create -yn tensorflow
# source activate tensorflow
# pip install --ignore-installed --upgrade https://storage.googleapis.com/tensorflow/linux/cpu/tensorflow-1.1.0-cp35-cp35m-linux_x86_64.whl
# source deactivate


# ----------------------------------------------------------------------
#        Download NLTK
# ----------------------------------------------------------------------

sudo $HOME/anaconda/bin/python -c "import nltk; \
nltk.download('stopwords', '/mnt/usr-moved/share/nltk_data'); \
nltk.download('punkt', '/mnt/usr-moved/share/nltk_data'); \
nltk.download('averaged_perceptron_tagger', '/mnt/usr-moved/share/nltk_data'); \
nltk.download('maxent_treebank_pos_tagger', '/mnt/usr-moved/share/nltk_data')"


# ----------------------------------------------------------------------
#                         Install Theano
# ----------------------------------------------------------------------
conda install -y theano pygpu

# ----------------------------------------------------------------------
#                         Security Update
# ----------------------------------------------------------------------:
sudo yum -y update
sudo yum -y install tmux

```
Uncomment out the Keras/ Tensorflow to install that!
Keep in mind that the bootstrap file is basically just a list of commands for each node in the cluster to run, so you could add your own commands in there for custom installs.

Now we can go ahead and launch a cluster like before:
```
$ bash launch_cluster.sh s3-bucket-name spark 4
```
This should work now!

After your cluster boots up, you can save a little time configuring the port forwarding to access the Jupyter, Spark history and Ganglia servers with a bash script like this:

#### tunnel_config.sh

```
#!/bin/bash

# Takes one argument :
#   name of key file - without .pem extension = $1

# Configure Spark history
ssh -NfL 18080:localhost:18080 $1
# Configure Jupyter Notebook
ssh -NfL 48888:localhost:48888 $1
# Configure Ganglia
ssh -NfL 8157:localhost:80 $1
```
Once the cluster starts up and you run the above commands *on your local machine*, you can access the web interfaces like this:
Make sure you've put your master public DNS for your new cluster into your spark ssh file, otherwise it'll just sit there
```
$ bash tunnel_config.sh spark
```

| Service | Address in Web Browser     |
| :------------- | :------------- |
| Ganglia (it make take a 10-15 minutes for the graphs to initialize)            | 0.0.0.0:8157/ganglia/       |
| Jupyter (You will need a token to access this when you first start, you can just copy and paste out of the startup commands and change http://ip-172-31-14-224:48888/?token=0fc28476bfca0b387a018e218d8047ad819b631bef4e32c to http://0.0.0.0:4888/? etc...)             | 0.0.0.0:48888       |
| Spark History       | 0.0.0.0:18080       |

You can now get started with your work! Remember to change your jupyspark-emr.sh file to match your configuration

Tuning these spark jobs is it's own whole thing, but here's a quick guide:
http://c2fo.io/c2fo/spark/aws/emr/2016/09/01/apache-spark-config-cheatsheet-part2/

Here's a link to a google doc you can use to tune your spark setup: change the values in green https://docs.google.com/spreadsheets/d/1dQhkmEuP_yzFestvJRJOcmHjJwdctaY3pGycaRrGiJs/edit?usp=sharing

For a five node c3.2xlarge:
Each node has 15GiBs of memory, 8vCPUs and we have four workers (you can find this under hardware on your EMR cluster status page) :
<img src="img/EMR.jpg" width = 800>
So:
Master Memory	15
Master Cores	8
Number of Worker Nodes	4
Memory Per Worker Node (GB)	15
Cores Per Worker Node	8

Now you have to pick executors per node. The grid just below the values you entered will gray out bad numbers of Executors per Node -- use the first or second number after the last grayed out value, and enter it in Selected Executors Per Node, and it will tell you what to do!
<img src="img/spark_config.jpg" width = 800>

I've entered my values below:


```
#!/bin/bash
source ~/.bashrc
export SPARK_HOME=/usr/lib/spark
export PYTHONPATH=${SPARK_HOME}/python:$PYTHONPATH
export PYSPARK_PYTHON=$HOME/anaconda/bin/python
export PYSPARK_DRIVER_PYTHON=jupyter
export PYSPARK_DRIVER_PYTHON_OPTS="notebook --no-browser --NotebookApp.ip='0.0.0.0' --NotebookApp.port=48888"

${SPARK_HOME}/bin/pyspark \
	--master yarn \
        --deploy-mode client \
  --num-executors 12
	--executor-memory 3G \
        --executor-cores 2 \
	--driver-memory 12G \
        --driver-cores 5 \
	--packages com.databricks:spark-csv_2.11:1.5.0 \
	--packages com.amazonaws:aws-java-sdk-pom:1.10.34 \
	--packages org.apache.hadoop:hadoop-aws:2.7.3
```

I've included my bash files in the repo, hopefully they're helpful!
Thanks for reading, hope this was helpful!
