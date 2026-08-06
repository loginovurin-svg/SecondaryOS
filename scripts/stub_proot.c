#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

int main(int argc, char *argv[]) {
    const char *status_path = NULL;
    
    // Ищем путь к status.txt в аргументах
    for (int i = 1; i < argc; i++) {
        if (strstr(argv[i], "status.txt")) {
            status_path = argv[i];
            break;
        }
    }
    
    fprintf(stdout, "stub_proot: STARTED, argc=%d\n", argc);
    fflush(stdout);
    
    if (!status_path) {
        fprintf(stderr, "stub_proot: status.txt path not found\n");
        return 1;
    }
    
    fprintf(stdout, "stub_proot: status_path=%s\n", status_path);
    fflush(stdout);
    
    // Создаём файл
    int fd = open(status_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        fprintf(stderr, "stub_proot: open failed\n");
        return 1;
    }
    
    const char *msg = "CONTAINER_ALIVE\n";
    write(fd, msg, strlen(msg));
    close(fd);
    
    fprintf(stdout, "stub_proot: SUCCESS\n");
    fprintf(stdout, "Minimal shell working\n");
    fflush(stdout);
    
    return 0;
}
