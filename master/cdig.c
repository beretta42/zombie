#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/ip.h>
#include <arpa/inet.h>
#include <error.h>
#include <signal.h>

#include "zombie.h"

struct sockaddr_in laddr;
struct sockaddr_in raddr;
int sd;


void cb_alarm(int sig)
{
}


void main(int argc, char *argv[])
{
    int ret;

    if (argc < 2) {
	fprintf(stderr,"cdig username\n");
	exit(1);
    }
  
    /* setup local address */
    memset(&laddr, 0, sizeof(laddr));
    laddr.sin_family = AF_INET;
    inet_aton("192.168.42.1", &laddr.sin_addr);
    /* setup remote address */
    memset(&raddr, 0, sizeof(raddr));
    raddr.sin_family = AF_INET;
    raddr.sin_port = htons(6999);
    inet_aton("192.168.42.1", &raddr.sin_addr);
 
    sd = socket(AF_INET, SOCK_DGRAM, 0);
    if (!sd){
	perror("socket");
	exit(1);
    }

    struct sigaction a;
    a.sa_handler = cb_alarm;
    a.sa_flags = 0;
    sigaction(SIGALRM, &a, NULL);

    int retries = 3;
    while (retries--){
	memset(buf, 0, sizeof(buf));
	b_op = MT_QUERY;
	strcpy(b_data, argv[1]);
	ret = sendto(sd, buf, 8 + strlen(argv[1])+1, 0,
		     (struct sockaddr *)&raddr, sizeof(raddr));
	alarm(1);
	ret = recvfrom(sd, buf, BUFLEN, 0,
		       NULL, NULL);
	if (ret > 0){
	    if (b_op != (MT_QUERY|MT_RESP))
		continue;
	    if (b_ret != 0){
		fprintf(stderr,"node %s not found\n", argv[1]);
		exit(1);
	    }
	    printf("reply!\n");
	    exit(0);
	}
    }
    fprintf(stderr,"timeout\n");
    exit(1);
}
