/*
 * stub_proot.c — минимальная заглушка proot (ELF aarch64)
 * Создаёт файл status.txt в текущей working directory
 * БЕЗ system(), БЕЗ сложных вызовов
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>

int main(int argc, char *argv[]) {
    // Выводим отладку
    printf("stub_proot: STARTED\n");
    printf("stub_proot: argc=%d\n", argc);
    fflush(stdout);
    
    // Парсим аргументы (пропускаем -r, -b, но не используем их)
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-r") == 0 && i + 1 < argc) {
            printf("stub_proot: rootfs=%s\n", argv[i + 1]);
            i++;
        } else if (strcmp(argv[i], "-b") == 0 && i + 1 < argc) {
            printf("stub_proot: bind=%s\n", argv[i + 1]);
            i++;
        }
    }
    
    // Создаём файл status.txt в текущей working directory
    // (которую установит MainActivity через pb.directory())
    const char *status_path = "status.txt";
    
    printf("stub_proot: creating %s\n", status_path);
    fflush(stdout);
    
    int fd = open(status_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        fprintf(stderr, "stub_proot: FAILED to open %s\n", status_path);
        perror("open");
        fflush(stderr);
        return 1;
    }
    
    const char *msg = "CONTAINER_ALIVE\n";
    ssize_t written = write(fd, msg, strlen(msg));
    close(fd);
    
    if (written > 0) {
        printf("stub_proot: SUCCESS - wrote %zd bytes\n", written);
        printf("Minimal shell working\n");
        fflush(stdout);
        return 0;
    } else {
        fprintf(stderr, "stub_proot: FAILED to write\n");
        perror("write");
        fflush(stderr);
        return 1;
    }
}
