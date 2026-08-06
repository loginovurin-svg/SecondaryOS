/*
 * stub_proot.c — минимальная заглушка proot (ELF aarch64)
 * Просто создаёт файл status.txt с CONTAINER_ALIVE
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    char *root_dir = NULL;
    char *status_file = NULL;
    
    // Парсим аргументы proot
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-r") == 0 && i + 1 < argc) {
            root_dir = argv[i + 1];
            i++;
        } else if (strcmp(argv[i], "-b") == 0) {
            i++; // пропускаем bind
        } else if (strcmp(argv[i], "-c") == 0 && i + 1 < argc) {
            // Ищем путь к status.txt в команде
            char *cmd = argv[i + 1];
            char *pos = strstr(cmd, ">");
            if (pos) {
                pos++; // пропускаем '>'
                while (*pos == ' ') pos++; // пропускаем пробелы
                // Копируем путь до следующего пробела или &
                char path[512] = {0};
                int j = 0;
                while (*pos && *pos != ' ' && *pos != '&' && j < 511) {
                    path[j++] = *pos++;
                }
                status_file = strdup(path);
            }
            i++;
        }
    }
    
    printf("stub_proot: root=%s\n", root_dir ? root_dir : "(null)");
    printf("stub_proot: status_file=%s\n", status_file ? status_file : "(null)");
    
    // Создаём файл status.txt
    if (status_file) {
        FILE *f = fopen(status_file, "w");
        if (f) {
            fprintf(f, "CONTAINER_ALIVE\n");
            fclose(f);
            printf("stub_proot: created %s\n", status_file);
            printf("Minimal shell working\n");
            free(status_file);
            return 0;
        } else {
            printf("stub_proot: failed to create %s\n", status_file);
            free(status_file);
            return 1;
        }
    }
    
    printf("stub_proot: no status file found\n");
    return 1;
}
