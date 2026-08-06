#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

int main(int argc, char *argv[]) {
    printf("stub_proot: STARTED\n");
    fflush(stdout);
    
    // Создаём status.txt в текущей working directory
    int fd = open("status.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        printf("stub_proot: open failed\n");
        return 1;
    }
    
    const char *msg = "CONTAINER_ALIVE\n";
    write(fd, msg, strlen(msg));
    close(fd);
    
    printf("stub_proot: SUCCESS\n");
    printf("Minimal shell working\n");
    fflush(stdout);
    
    return 0;
}
