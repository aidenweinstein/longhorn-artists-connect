// Placeholder conversations until messages come from CloudKit.
export type Message = { fromMe: boolean; text: string };
export type Conversation = {
  id: string;
  name: string;
  lastMessage: string;
  timestamp: string;
  unread: boolean;
  /** The thread, oldest first. Without it the open view shows just the last message. */
  messages?: Message[];
};

export const CONVERSATIONS: Conversation[] = [
  {
    id: "c1",
    name: "Maya Torres",
    lastMessage: "Are you still free to shoot Saturday? We moved call time to 8.",
    timestamp: "2:14 PM",
    unread: true,
    messages: [
      { fromMe: false, text: "Hey! Loved your reel. Want to DP my short?" },
      { fromMe: true, text: "Absolutely, send me the script" },
      { fromMe: false, text: "Are you still free to shoot Saturday? We moved call time to 8." },
    ],
  },
  { id: "c2", name: "Dev Patel", lastMessage: "Sent you the stems — let me know what you think of the mix.", timestamp: "11:02 AM", unread: true },
  { id: "c3", name: "Isabel Cruz", lastMessage: "Thanks for applying to Undertow! Can you send a reel?", timestamp: "Yesterday", unread: false },
  { id: "c4", name: "Jordan Lee", lastMessage: "Those golden hour shots came out so good", timestamp: "Yesterday", unread: false },
  { id: "c5", name: "Sam Rivera", lastMessage: "You: I can do the poster by Friday", timestamp: "Mon", unread: false },
  { id: "c6", name: "Priya Shah", lastMessage: "Let's grab coffee and talk about the album art", timestamp: "Oct 28", unread: false },
];
