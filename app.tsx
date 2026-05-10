import React, {useEffect, useState} from 'react';
import {render, Box, Text} from 'ink';

function App() {
  const [seconds, setSeconds] = useState(0);

  useEffect(() => {
    const timer = setInterval(() => {
      setSeconds(s => s + 1);
    }, 1000);

    return () => clearInterval(timer);
  }, []);

  return (
    <Box borderStyle="round" paddingX={1}>
      <Text>
        🚀 Claude RUN │ time {seconds}s │ files 0 │ warn 0
      </Text>
    </Box>
  );
}

render(<App />);