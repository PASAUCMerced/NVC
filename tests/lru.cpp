/**
 * Your LRUCache object will be instantiated and called as such:
 * LRUCache* obj = new LRUCache(capacity);
 * int param_1 = obj->get(key);
 * obj->put(key,value);
 */

struct Node{
    int key;
    Node *next, *pre;
    Node(int k):key(k), next(NULL), pre(NULL){}
};
class LRUCache {
public:
    int size, count;
    Node *head = new Node(0);
    unordered_map<int, Node*> m;

    LRUCache(int capacity) {
        size = capacity;
        count = 0;
        head->next = head;
        head->pre = head;
    }

    void setsize
// no value need
/*
    int get(int key) {
        if(m.count(key)==0) return -1;
        Node *tmp = m[key];
        delNode(tmp);
        pushHead(tmp);
        //cout<<"get and erase"<<key<<endl;
        return tmp->value;
    }
*/
    void put(int key) {
        if(m.count(key)==0){
            if(count==size){
                //cout<<"too long and erase "<<head->pre->key<<endl;
                m.erase(head->pre->key);
                delNode(head->pre);
                count--;
            }
            count++;
            Node *tmp = new Node(key);
            pushHead(tmp);
            m[key]=tmp;
        }
        else{
            Node *tmp = m[key];
            delNode(tmp);
            //cout<<"put and erase "<<tmp->key<<endl;
            pushHead(tmp);
        }
    }

    void delNode(Node *p){
        p->pre->next = p->next;
        p->next->pre = p->pre;
    }
    void pushHead(Node *p){
       p->next = head->next;
       head->next = p;
       p->next->pre = p;
       p->pre = head;
    }
};

int main()
{
  LRUCache* obj = new LRUCache(64);
  obj->put(1);
  return 0;
}
