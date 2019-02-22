#include <stdlib.h>
#include <jni.h>

static const char *const messages[] = {
        "Hello, world!",
        "Hej världen!",
        "Bonjour, monde!",
        "Hallo Welt!"
};

int (*rand_ptr)() = rand;

extern void Java_net_hanshq_hello_MainActivity_loadDFM();
void *loader_ptr = Java_net_hanshq_hello_MainActivity_loadDFM;

JNIEXPORT jstring JNICALL
Java_net_hanshq_hello_MainActivity_getMessage(JNIEnv *env, jobject obj)
{
        int i;

        i = rand_ptr() % (sizeof(messages) / sizeof(messages[0]));

        return (*env)->NewStringUTF(env, messages[i]);
}

JNIEXPORT void init(JNIEnv *env) {
  volatile void *loader = loader_ptr;
}
