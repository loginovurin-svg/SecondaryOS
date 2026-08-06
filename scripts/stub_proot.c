/*
 * stub_proot.c — минимальная заглушка proot (ELF aarch64)
 * ТОЛЬКО системные вызовы: write(), open(), close()
 * БЕЗ stdio, БЕЗ fflush, БЕЗ fprintf
 */
#include <unistd.h>
#include <fcntl.h>
#include <string.h>

// Простая функция для вывода строки (без буферизации)
static void write_str(const char *str) {
    write(STDOUT_FILENO, str, strlen(str));
}

// Простая функция для вывода числа
static void write_num(int num) {
    char buf[16];
    int i = sizeof(buf) - 1;
    buf[i] = '\n';
    
    if (num == 0) {
        buf[--i] = '0';
    } else {
        while (num > 0 && i > 0) {
            buf[--i] = '0' + (num % 10);
            num /= 10;
        }
    }
    
    write(STDOUT_FILENO, &buf[i], sizeof(buf) - i);
}

int main(int argc, char *argv[]) {
    const char *msg_start = "stub_proot: STARTED\n";
    const char *msg_success = "stub_proot: SUCCESS\nMinimal shell working\n";
    const char *msg_failed = "stub_proot: FAILED\n";
    
    // Выводим "STARTED"
    write_str(msg_start);
    
    // Создаём файл status.txt в текущей working directory
    const char *filename = "status.txt";
    int fd = open(filename, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    
    if (fd < 0) {
        write_str("stub_proot: open failed\n");
        return 1;
    }
    
    // Записываем CONTAINER_ALIVE
    const char *content = "CONTAINER_ALIVE\n";
    ssize_t written = write(fd, content, strlen(content));
    close(fd);
    
    if (written > 0) {
        write_str(msg_success);
        return 0;
    } else {
        write_str(msg_failed);
        return 1;
    }
}
